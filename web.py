#!/usr/bin/env python3
"""aria2's live view: a small web server inside iSH-AOK, for the shortcut's Show Web Page.

dl starts it (see web_link in dl) when the live view or the player is asked for, and it
stops by itself after five minutes without a request. It shows:
  /            every download, with progress bars that move as the downloads do
  /play/<id>   a finished download, played right there (videos, music, pictures)
  /file/<id>   the file itself, in ranges, as Safari's player asks for it
It reads what dl writes, the logs in .logs, the way dl's load() does: keep the two in step.
What it changes, it asks dl to do (dl --act, dl -b).

It listens on 127.0.0.1 only, checks the Host header, and every request but /ping needs the
token dl made for it, so other apps and web pages on the phone can't use it.

    python3 web.py <port> <token>
with WEB_DEST, WEB_SHARE, WEB_SHARE_HOST and WEB_DL (the dl script) in the environment.
"""
import base64
import html
import json
import mimetypes
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, TOKEN = int(sys.argv[1]), sys.argv[2]
DEST = os.environ["WEB_DEST"]
JOBS = os.path.join(DEST, ".logs")
SHARE = os.environ["WEB_SHARE"]
SHARE_HOST = os.environ.get("WEB_SHARE_HOST", "")  # the iOS path of the folder at SHARE
DL = os.environ["WEB_DL"]
IDLE = 300  # seconds without a request before it stops
last_request = time.time()

for kind, ext in (("video/mp4", ".mp4"), ("video/mp4", ".m4v"), ("audio/mp4", ".m4a"),
                  ("video/quicktime", ".mov"), ("video/webm", ".webm"), ("audio/mpeg", ".mp3")):
    mimetypes.add_type(kind, ext)


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def alive(job):
    """Is the job's worker (`sh dl --work <id>`) running, and not a zombie?"""
    pid = read(os.path.join(JOBS, f"{job}.pid")).strip()
    if not pid.isdigit():
        return False
    stat = read(f"/proc/{pid}/stat")
    if not stat or stat[stat.rfind(")") + 2:][:1] == "Z":
        return False
    return re.search(rf"--work {job} *$", read(f"/proc/{pid}/cmdline").replace("\0", " ")) is not None


def last(pattern, lines):
    found = [m for m in (re.match(pattern, line) for line in lines) if m]
    return found[-1] if found else None


# What yt-dlp is doing before a download starts, as dl's preparing() has it.
STEPS = [("Extracting URL", 8, "opening the link"), ("Downloading webpage", 15, "reading the page"),
         ("API JSON", 25, "asking for the formats"), ("Downloading player", 35, "getting YouTube's player"),
         ("Solving JS challenges", 50, "unlocking the video link, about a minute"),
         ("Extracting information", 50, "looking for the video"), ("m3u8", 80, "getting the list of streams"),
         ("MPD", 80, "getting the list of streams"), ("format(s)", 95, "about to start")]


def link_name(link):
    """Something to call a download before its name is known, roughly as dl's link_name."""
    if link.startswith("magnet:"):
        m = re.search(r"[?&]dn=([^&]*)", link)
        return urllib.parse.unquote_plus(m.group(1)) if m else "magnet link"
    last_part = re.sub(r"[?#].*", "", link).rstrip("/").rsplit("/", 1)[-1]
    if "." not in last_part:  # a page, not a file: most likely a video's
        host = re.sub(r"^[a-z]+://(www\.)?([^/:?#]*).*", r"\2", link.lower())
        return f"{host} video"
    return last_part


def has(path):
    return os.path.exists(path) and os.path.getsize(path) > 0


def job(i):
    """One download, as dl's load() reads it."""
    text = read(os.path.join(JOBS, f"{i}.log"))
    link = text.split("\n", 1)[0]
    start = text.rfind("\n=== start")
    seg = text[start + 1:] if start >= 0 else text
    lines = seg.split("\n")
    code = last(r"=== exit (\d+)", lines)
    reason = ""
    if "=== stopped" in seg:
        state = "done"
    elif "=== paused" in seg:
        state = "paused"
    elif code:
        state = "done" if code.group(1) == "0" else "failed"
        m = last(r".*errorCode=|ERROR: ", lines)
        if m:
            reason = m.string
            for pattern in (r".*errorCode=\d* ", r"^ERROR: ", r"^\[[^]]*\] [^:]*: "):  # as dl's sed does
                reason = re.sub(pattern, "", reason, count=1)
            reason = "no video found on this page" if reason.startswith("Unsupported URL") else reason[:120]
    else:
        state = "running" if alive(i) else "paused"
    prog = last(r"\[#.*", lines)
    pct = speed = eta = None
    if prog:
        m = re.search(r"\( *(\d+)[.\d]*%\)", prog.string)
        pct = int(m.group(1)) if m else None
        m = re.search(r" DL: *([^\] ]*)", prog.string)
        speed = m.group(1).removesuffix("/s") if m else None
        m = re.search(r" ETA:([^\]]*)\]", prog.string)
        eta = m.group(1) if m and m.group(1) != "NA" else None
    files = [line[6:] for line in lines if line.startswith("FILE: ") and "[METADATA]" not in line]
    path = files[-1] if files else ""
    name = os.path.basename(path)
    if not name:
        m = last(r"NAME: (.*)", lines)
        name = m.group(1) if m else link_name(link)
    via = "yt-dlp" if "=== via yt-dlp" in seg else "aria2"
    if state == "done" and via == "yt-dlp" and path:
        name = os.path.splitext(name)[0]
    m = last(r"=== size (.*)", lines)
    size = m.group(1) if m else ""
    steps = [line for line in lines if re.match(r"\[[A-Za-z:_]+\] ", line) and not re.match(r"\[(Exec|download|debug)\]", line)]
    step = re.sub(r"^(\[[^]]*\] )*", "", steps[-1]) if steps else ""
    step = re.sub(r"^[^ :]*: ", "", step)[:48]
    moving = "=== moving to Files" in seg
    prep, label = 3, "starting"
    if link.startswith("magnet:") and not step:
        prep, label = 10, "looking for peers"
    elif step:
        prep, label = next(((p, l) for key, p, l in STEPS if key in step), (50, step))
    out = {"id": i, "link": link, "title": name, "state": state, "pct": pct, "speed": speed, "eta": eta,
           "size": size, "reason": reason, "moving": moving, "prep": prep, "label": label,
           "thumb": has(os.path.join(JOBS, f"{i}.thumb"))}
    pl = last(r"\[download\] Downloading playlist: (.*)", lines)
    if pl:
        item = last(r"\[download\] Downloading item (\d+) of (\d+)$", lines)
        n, total = (int(item.group(1)), int(item.group(2))) if item else (1, 1)
        videos = sum(1 for f in files if f.startswith(DEST + "/"))
        errors = sum(1 for line in lines if line.startswith("ERROR: "))
        if state == "failed" and videos:
            state = "done"
        out.update(title=pl.group(1), state=state, playlist=True, n=n, total=total, videos=videos,
                   errors=errors, stopped="=== stopped" in seg, overall=((n - 1) * 100 + (pct or 0)) // total)
        if path.startswith(DEST + "/") and "/" in path[len(DEST) + 1:]:
            path = os.path.dirname(path)
    out["path"] = path
    if path.startswith(SHARE + "/") and SHARE_HOST.startswith("/"):
        where = path if os.path.isdir(path) or out.get("playlist") else os.path.dirname(path)
        out["folder"] = "shareddocuments://" + urllib.parse.quote(SHARE_HOST + where[len(SHARE):])
    return out


def jobs():
    ids = sorted((int(f[:-4]) for f in os.listdir(JOBS) if f.endswith(".log") and f[:-4].isdigit()), reverse=True)
    return [job(i) for i in ids[:10]]


def inside(path, top):
    path, top = os.path.realpath(path), os.path.realpath(top)
    return path == top or path.startswith(top + os.sep)


def target(i, rel=""):
    """The file of a finished download (or one in its folder), if it's in Downloads or Files."""
    j = job(i)
    path = j["path"]
    if j["state"] != "done" or not path or not (inside(path, SHARE) or inside(path, DEST)):
        return None
    if rel:
        full = os.path.join(path, rel)
        return full if inside(full, path) and os.path.isfile(full) else None
    return path if os.path.exists(path) else None


def kind(path):
    t = mimetypes.guess_type(path)[0] or ""
    return t.split("/")[0] if t.split("/")[0] in ("video", "audio", "image") else ""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, body, content_type="text/html; charset=utf-8", headers=()):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def allowed(self, query):
        global last_request
        host = self.headers.get("Host", "")
        if host not in (f"127.0.0.1:{PORT}", f"localhost:{PORT}"):
            return False
        if query.get("t", [""])[0] != TOKEN and self.headers.get("X-Token") != TOKEN:
            return False
        last_request = time.time()
        return True

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/ping":
            return self.send(200, "ok", "text/plain")
        if not self.allowed(query):
            return self.send(403, "Open this from the aria2 shortcut.", "text/plain")
        if url.path == "/hello":  # is this the server with this token? (dl's web_link)
            return self.send(200, "ok", "text/plain")
        t = "?t=" + TOKEN
        if url.path == "/":
            return self.send(200, PAGE.replace("{{TOKEN}}", TOKEN))
        if url.path == "/status":
            return self.send(200, json.dumps({"jobs": jobs()}), "application/json")
        m = re.fullmatch(r"/(thumb|play|file|report)/(\d+)", url.path)
        if not m:
            return self.send(404, "Not found", "text/plain")
        what, i = m.group(1), int(m.group(2))
        if what == "report":  # dl's debug report, with a button that copies it
            text = subprocess.run(["sh", DL, "--report", str(i)], capture_output=True, text=True, timeout=60).stdout
            return self.send(200, REPORT.format(token=TOKEN, text=html.escape(text)))
        if what == "thumb":
            data = read(os.path.join(JOBS, f"{i}.thumb")).strip()
            return self.send(200, base64.b64decode(data), "image/jpeg") if data else self.send(404, "", "text/plain")
        rel = query.get("f", [""])[0]
        path = target(i, rel)
        if not path:
            return self.send(404, PLAYER.format(title="Not found", body="<p>That file isn't there any more. "
                             "Try <b>Download again</b> in aria2.</p>"))
        if what == "file":
            return self.file(path)
        title = html.escape(os.path.basename(path))
        if os.path.isdir(path):
            names = sorted(f for f in os.listdir(path) if not f.startswith(".") and os.path.isfile(os.path.join(path, f)))
            items = "".join(f'<li><a href="/play/{i}{t}&f={urllib.parse.quote(f)}">{html.escape(f)}</a></li>' for f in names)
            return self.send(200, PLAYER.format(title=title, body=f"<ul>{items}</ul>"))
        src = f"/file/{i}{t}" + (f"&f={urllib.parse.quote(rel)}" if rel else "")
        body = {"video": f'<video src="{src}" controls autoplay playsinline></video>',
                "audio": f'<audio src="{src}" controls autoplay></audio>',
                "image": f'<img src="{src}" alt="">'}.get(kind(path))
        if not body:  # Safari shows PDFs and text itself, and offers to save anything else
            return self.send(303, "", headers=[("Location", src)])
        return self.send(200, PLAYER.format(title=title, body=body))

    def file(self, path):
        size = os.path.getsize(path)
        start, end = 0, size - 1
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                start, end = int(m.group(1)), min(int(m.group(2) or end), end)
            else:
                start = max(size - int(m.group(2)), 0)
            if start > end:
                return self.send(416, "", "text/plain", [("Content-Range", f"bytes */{size}")])
        self.send_response(206 if m else 200)
        self.send_header("Content-Type", mimetypes.guess_type(path)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        if m:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            return
        try:
            with open(path, "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = f.read(min(left, 256 * 1024))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the player only wanted part of it

    def do_POST(self):
        url = urllib.parse.urlsplit(self.path)
        if not self.allowed(urllib.parse.parse_qs(url.query)):
            return self.send(403, "", "text/plain")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self.send(400, "", "text/plain")
        if url.path == "/act" and str(body.get("id", "")).isdigit() and body.get("do") in ("pause", "resume", "stop", "again"):
            args = ["--act", str(body["id"]), body["do"]]
        elif url.path == "/add" and isinstance(body.get("text"), str):
            args = ["-b", base64.b64encode(body["text"].encode()).decode()]
        else:
            return self.send(400, "", "text/plain")
        out = subprocess.run(["sh", DL, *args], capture_output=True, text=True, timeout=90).stdout.strip()
        return self.send(200, json.dumps({"message": out}), "application/json")


def watch(server):
    """Keep iSH-AOK awake while the page is in use (dl's keep_awake), and stop when it isn't."""
    while time.time() - last_request < IDLE:
        subprocess.run(["sh", DL, "--awake"], capture_output=True)
        time.sleep(15)
    server.shutdown()


REPORT = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark"><title>Debug report</title>
<style>
body {{ margin: 0; padding: 12px 16px 32px; font: 15px -apple-system, system-ui, sans-serif; }}
p {{ color: #8e8e93; margin: 4px 0 12px; }}
button {{ font: inherit; font-weight: 600; border: none; border-radius: 12px; padding: 11px 16px; background: #0a84ff; color: #fff; }}
pre {{ font: 11px ui-monospace, Menlo, monospace; white-space: pre-wrap; word-break: break-all; }}
</style></head><body>
<p>What aria2 knows about this download. Copy it, then paste it into a message to whoever helps you.</p>
<button onclick="navigator.clipboard.writeText(document.querySelector('pre').textContent)
  .then(() => this.textContent = 'Copied', () => alert('Select the text and copy it instead.'))">Copy the report</button>
<pre>{text}</pre></body></html>"""

PLAYER = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark"><title>{title}</title>
<style>
body {{ margin: 0; background: #000; color: #fff; font: 16px -apple-system, system-ui, sans-serif; min-height: 100vh;
  display: flex; flex-direction: column; justify-content: center; }}
h1 {{ font-size: 17px; font-weight: 600; margin: 16px; text-align: center; word-break: break-word; }}
video, img {{ width: 100%; max-height: 80vh; object-fit: contain; background: #000; }}
audio {{ width: calc(100% - 32px); margin: 0 16px; }}
ul {{ list-style: none; padding: 0 16px; }} li a {{ display: block; padding: 14px 0; color: #0a84ff;
  border-bottom: 1px solid #333; text-decoration: none; }} p {{ margin: 16px; text-align: center; }}
</style></head><body><h1>{title}</h1>{body}</body></html>"""

PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark"><title>aria2</title>
<style>
@property --p { syntax: "<number>"; inherits: false; initial-value: 0; }  /* so the ring can glide */
:root { --bg: #f2f2f7; --card: #fff; --text: #000; --sub: #6e6e73; --track: #e5e5ea; --blue: #0a84ff;
  --orange: #ff9f0a; --green: #30d158; --red: #ff453a; --gray: #8e8e93; --button: #e9e9eb; }
@media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --text: #fff; --sub: #98989f;
  --track: #38383a; --button: #2c2c2e; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px -apple-system, system-ui, sans-serif;
  padding: 8px 16px calc(24px + env(safe-area-inset-bottom)); -webkit-tap-highlight-color: transparent; }
h1 { font-size: 30px; margin: 12px 0 2px; letter-spacing: -0.5px; }
#summary { color: var(--sub); margin-bottom: 14px; font-variant-numeric: tabular-nums; }
form { display: flex; gap: 8px; margin-bottom: 16px; }
input { flex: 1; min-width: 0; font: inherit; padding: 11px 12px; border-radius: 12px; border: none;
  background: var(--card); color: var(--text); }
button, .button { font: inherit; font-weight: 600; border: none; border-radius: 999px; padding: 8px 14px;
  background: var(--button); color: var(--blue); text-decoration: none; display: inline-block; }
form button { background: var(--blue); color: #fff; border-radius: 12px; }
.card { background: var(--card); border-radius: 16px; padding: 12px; margin-bottom: 10px; display: grid;
  grid-template-columns: 56px 1fr; gap: 4px 12px; align-items: center; scroll-margin: 16px; }
.card.focus { box-shadow: 0 0 0 2px var(--blue); }
.pic { width: 56px; height: 56px; border-radius: 50%; position: relative; display: grid; place-items: center;
  background: conic-gradient(var(--c) calc(var(--p) * 1%), var(--track) 0); transition: --p 1s linear;
  font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; }
.pic::before { content: ""; position: absolute; inset: 5px; border-radius: 50%; background: var(--card); }
.pic img, .pic span { position: relative; }
.pic img { width: 46px; height: 46px; border-radius: 50%; object-fit: cover; }
.title { font-weight: 600; line-height: 1.25; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 2;
  -webkit-box-orient: vertical; word-break: break-word; }
.line { color: var(--sub); font-size: 13px; margin-top: 2px; font-variant-numeric: tabular-nums; }
.bar { grid-column: 1 / -1; height: 6px; border-radius: 3px; background: var(--track); overflow: hidden; margin-top: 8px; }
.bar i { display: block; height: 100%; width: 0; border-radius: 3px; background: var(--c); transition: width 1s linear; }
.bar.waiting i { width: 100% !important; opacity: 0.5; animation: wait 1.2s ease-in-out infinite alternate; }
@keyframes wait { from { transform: translateX(-70%); } to { transform: translateX(70%); } }
.actions { grid-column: 1 / -1; display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px; }
.actions:empty { display: none; }
.danger { color: var(--red); }
#empty { color: var(--sub); text-align: center; margin-top: 40px; }
#toast { position: fixed; left: 16px; right: 16px; bottom: calc(16px + env(safe-area-inset-bottom)); padding: 12px 14px;
  border-radius: 14px; background: rgba(60, 60, 67, 0.92); color: #fff; opacity: 0; transition: opacity 0.3s;
  pointer-events: none; }
#toast.on { opacity: 1; }
</style></head><body>
<h1>Downloads</h1>
<div id="summary">Loading…</div>
<form id="add"><input id="link" type="url" placeholder="Paste a link to download" autocomplete="off">
<button>Download</button></form>
<main id="list"></main>
<div id="empty" hidden>Nothing here yet. Share a link to aria2, or paste one above.</div>
<div id="toast"></div>
<script>
const token = "{{TOKEN}}";
const colours = { running: "var(--blue)", preparing: "var(--orange)", paused: "var(--gray)",
  done: "var(--green)", failed: "var(--red)" };
const cards = {};
let focus = location.hash.slice(1);

function el(tag, cls, parent) { const e = document.createElement(tag); if (cls) e.className = cls;
  if (parent) parent.appendChild(e); return e; }

function toast(text) { const t = document.getElementById("toast"); t.textContent = text; t.classList.add("on");
  clearTimeout(t.timer); t.timer = setTimeout(() => t.classList.remove("on"), 2500); }

async function post(path, body) {
  const r = await fetch(path, { method: "POST", headers: { "X-Token": token, "Content-Type": "application/json" },
    body: JSON.stringify(body) });
  const answer = await r.json(); if (answer.message) toast(answer.message.split("\n")[0]); refresh();
}

// What a download's card says: its colour, how full its ring and bar are, and its line.
function looks(j) {
  if (j.state === "running" && j.moving) return ["running", 100, "Moving to Files…", false];
  if (j.state === "running" && j.playlist)
    return [j.pct == null ? "preparing" : "running", j.overall,
      `Video ${j.n} of ${j.total} · ` + (j.pct == null ? `preparing · ${j.label}…` : `${j.pct}% · ${j.speed || "0B"}/s`), j.pct == null];
  if (j.state === "running" && j.pct != null)
    return ["running", j.pct, `${j.pct}% · ${j.speed || "0B"}/s` + (j.eta ? ` · ${j.eta} left` : ""), false];
  if (j.state === "running") return ["preparing", j.prep, `Preparing ${j.prep}% · ${j.label}…`, true];
  if (j.state === "paused") return ["paused", j.playlist ? j.overall : (j.pct || 0),
    j.playlist ? `Paused · video ${j.n} of ${j.total}` : "Paused" + (j.pct != null ? ` at ${j.pct}%` : ""), false];
  if (j.state === "done") {
    let line = j.playlist ? (j.stopped ? `Stopped · ${j.videos} of ${j.total} videos` :
      `${j.videos} videos` + (j.errors ? ` · ${j.errors} failed` : "")) : "Downloaded";
    return ["done", 100, line + (j.size ? ` · ${j.size}` : ""), false];
  }
  return ["failed", 100, "Failed" + (j.reason ? `: ${j.reason}` : ""), false];
}

function button(parent, text, action, cls) { const b = el("button", cls, parent); b.textContent = text;
  b.onclick = action; return b; }

function render(j) {
  let c = cards[j.id];
  if (!c) {
    c = cards[j.id] = { root: el("div", "card") };
    c.root.id = j.id;
    c.pic = el("div", "pic", c.root);
    const text = el("div", "", c.root);
    c.title = el("div", "title", text); c.line = el("div", "line", text);
    c.bar = el("div", "bar", c.root); c.fill = el("i", "", c.bar);
    c.actions = el("div", "actions", c.root);
  }
  const [state, pct, line, waiting] = looks(j);
  c.root.style.setProperty("--c", colours[state]);
  c.pic.style.setProperty("--p", pct);
  const pic = j.thumb ? `<img src="/thumb/${j.id}?t=${token}&v=${j.state}" alt="">` :
    `<span>${{ done: "✓", failed: "!", paused: "❚❚" }[state] || pct + "%"}</span>`;
  if (c.picHTML !== pic) { c.pic.innerHTML = pic; c.picHTML = pic; }
  c.title.textContent = j.title; c.line.textContent = line;
  c.bar.hidden = state === "done" || state === "failed";
  c.bar.classList.toggle("waiting", waiting);
  c.fill.style.width = pct + "%";
  const key = j.state + (j.folder || "") + (j.path || "");
  if (c.key !== key) {  // only rebuild the buttons when what they can do changes
    c.key = key; c.actions.innerHTML = "";
    if (j.state === "running") button(c.actions, "Pause", () => post("/act", { id: j.id, do: "pause" }));
    if (j.state === "paused") button(c.actions, "Resume", () => post("/act", { id: j.id, do: "resume" }));
    if (j.state === "failed") button(c.actions, "Try again", () => post("/act", { id: j.id, do: "resume" }));
    if (j.state === "failed") { const a = el("a", "button", c.actions); a.textContent = "Debug report";
      a.href = `/report/${j.id}?t=${token}`; }
    if (j.state === "done" && j.path) { const a = el("a", "button", c.actions); a.textContent = j.playlist ? "Videos" : "Open";
      a.href = `/play/${j.id}?t=${token}`; }
    if (j.state === "done" && j.folder) { const a = el("a", "button", c.actions); a.textContent = "Show in Files"; a.href = j.folder; }
    if (j.state === "done") button(c.actions, "Download again", () => post("/act", { id: j.id, do: "again" }));
    if (j.state === "running" || j.state === "paused")
      button(c.actions, "Stop", () => confirm(`Stop ${j.title}?`) && post("/act", { id: j.id, do: "stop" }), "danger");
  }
  return c.root;
}

async function refresh() {
  let data;
  try { data = await (await fetch("/status?t=" + token, { cache: "no-store" })).json(); }
  catch (e) { document.getElementById("summary").textContent = "aria2 isn't answering. Open the shortcut again."; return; }
  const list = document.getElementById("list"), seen = new Set();
  let running = 0, total = 0;
  data.jobs.forEach((j, n) => {
    seen.add(String(j.id));
    const root = render(j);
    if (list.children[n] !== root) list.insertBefore(root, list.children[n] || null);
    if (j.state === "running") { running++; total += speed(j.speed); }
  });
  for (const id of Object.keys(cards)) if (!seen.has(id)) { cards[id].root.remove(); delete cards[id]; }
  document.getElementById("empty").hidden = data.jobs.length > 0;
  document.getElementById("summary").textContent = running ?
    `${running} downloading · ${human(total)}/s` : "Nothing downloading right now";
  if (focus && cards[focus]) { cards[focus].root.classList.add("focus"); cards[focus].root.scrollIntoView(); focus = ""; }
}

function speed(s) {  // "1.2MiB" -> bytes
  const m = /([\d.]+)\s*([KMG]?)i?B/.exec(s || ""); return m ? m[1] * ({ "": 1, K: 1024, M: 1048576, G: 1073741824 }[m[2]]) : 0;
}
function human(b) { const u = ["B", "KB", "MB", "GB"]; let i = 0; while (b >= 1000 && i < 3) { b /= 1024; i++; }
  return (i ? b.toFixed(1) : Math.round(b)) + " " + u[i]; }

document.getElementById("add").onsubmit = e => { e.preventDefault(); const input = document.getElementById("link");
  if (input.value.trim()) post("/add", { text: input.value }); input.value = ""; input.blur(); };
refresh();
setInterval(() => { if (document.visibilityState === "visible") refresh(); }, 1000);
</script></body></html>"""


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    threading.Thread(target=watch, args=(server,), daemon=True).start()
    try:
        server.serve_forever()
    finally:
        subprocess.run(["sh", DL, "--rest"], capture_output=True)  # let iSH-AOK sleep, unless downloads run
