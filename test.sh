#!/bin/sh
# Checks dl on a computer, the way the iPhone runs it: BusyBox ash and BusyBox's text tools,
# links base64-encoded. Needs aria2c, yt-dlp, busybox, curl, ffmpeg, python3 (for a local web page
# with a video in it) and internet access. Run: sh test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
export DL_DIR="$tmp/Downloads"
# Stands in for the Files folder mounted at /mnt/phone: finished downloads move here.
export DL_SHARE="$tmp/Share"
export DL_TAPS=100000  # a run of the shortcut taps many times here; the limit has its own test
export DL_KEEP=1000  # the list keeps the newest 6 finished downloads; tests look at older ones
mkdir "$DL_SHARE"
# Stand-ins for /root/Shortcuts and for the setup script in the project's repository.
export DL_SHORTCUTS="$tmp/Shortcuts"
mkdir "$DL_SHORTCUTS"

# A local site: a page with a video in it, and a page without one.
mkdir "$tmp/www"
curl -sSL -o "$tmp/www/rabbit.mp4" \
  https://raw.githubusercontent.com/mdn/learning-area/main/html/multimedia-and-embedding/video-and-audio-content/rabbit320.mp4
# The video's poster is the picture the menus show for it (see thumb in dl).
printf '<!doctype html><title>Rabbit test page</title><video src="rabbit.mp4" poster="poster.png"></video>\n' \
  >"$tmp/www/video.html"
cp "$here/icons/done.png" "$tmp/www/poster.png"
printf '<!doctype html><title>Just text</title><p>No video here.</p>\n' >"$tmp/www/text.html"
cp "$tmp/www/rabbit.mp4" "$tmp/www/rabbit2.mp4"
printf '<!doctype html><title>Rabbit playlist</title><video src="rabbit.mp4"></video><video src="rabbit2.mp4"></video>\n' \
  >"$tmp/www/playlist.html"
printf '<!doctype html><title>Slow page</title><video src="rabbit2.mp4"></video>\n' >"$tmp/www/slow.html"
cp "$tmp/www/rabbit.mp4" "$tmp/www/rabbit3.mp4"
printf '<!doctype html><title>Stop test</title><video src="rabbit.mp4"></video><video src="rabbit3.mp4"></video>\n' \
  >"$tmp/www/stop.html"
port=18780
export DL_UPDATE_URL=http://127.0.0.1:$port/setup.sh
printf '#!/bin/sh\necho ran >>"%s/setup-runs"\nsha256sum <"$0" | cut -d" " -f1 >"$DL_DIR/.logs/.setup"\n' "$tmp" \
  >"$tmp/www/setup.sh"
# The server also stands in for Bark's: it takes notifications for the key GOODKEY42 and
# writes each one to bark.log, as JSON with its keys sorted.
export DL_BARK=http://127.0.0.1:$port/bark
cat >"$tmp/server.py" <<'PY'
import functools, http.server, json, sys
port, www, log = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path != "/bark/GOODKEY42":
            self.send_error(400, "failed to get device token")
            return
        try:
            line = json.dumps(json.loads(body), ensure_ascii=False, sort_keys=True)
        except ValueError:
            line = "NOT JSON: " + body.decode("utf-8", "replace")
        with open(log, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args):
        pass
handler = functools.partial(Handler, directory=www)
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
PY
python3 -I "$tmp/server.py" $port "$tmp/www" "$tmp/bark.log" >/dev/null 2>&1 &
server=$!
trap 'kill $server; pkill -f "$tmp"; pkill -f "$here/dl --work"; pkill -f "$here/web.py"; rm -rf "$tmp"' EXIT

# Alpine's BusyBox has nohup, pgrep and pkill; Ubuntu's doesn't, so those come from the system.
# aria2c and yt-dlp are slowed down so a download is still running when the checks look at it.
mkdir "$tmp/bin"
for tool in busybox sh awk base64 cat cp cut date dd df du find grep head ls mkdir mv od rm rmdir sed seq setsid sha256sum sleep sort stat tail timeout tr uname wc; do
  ln -s "$(command -v busybox)" "$tmp/bin/$tool"
done
for tool in nohup pgrep pkill kill curl ffmpeg python3; do ln -s "$(command -v $tool)" "$tmp/bin/$tool"; done
# The live view's server, from this folder, on a port of its own.
export DL_WEB="$here/web.py" DL_WEB_PORT=18781
# What lists a video's qualities, from this folder too.
export DL_FORMATS="$here/formats.py"
printf '<!doctype html><title>Quality test</title><video src="rabbit.mp4"></video>\n' >"$tmp/www/quality.html"
printf '<!doctype html><title>Audio test</title><video src="rabbit2.mp4"></video>\n' >"$tmp/www/audio.html"
printf '<!doctype html><title>Second playlist</title><video src="rabbit.mp4"></video><video src="rabbit2.mp4"></video>\n' \
  >"$tmp/www/list2.html"
printf 'third\n' >"$tmp/www/note3.txt"
printf '<!doctype html><title>%s</title><video src="rabbit.mp4"></video>\n' \
  "A title that makes a file name too long when it comes six times" >"$tmp/www/long.html"
# The menus' pictures, as setup installs them.
export DL_ICONS="$tmp/icons"
mkdir "$DL_ICONS"
for f in "$here"/icons/*.png; do name=${f##*/}; base64 -w 0 "$f" >"$DL_ICONS/${name%.png}.b64"; done
printf '#!/bin/sh\nexec %s --max-overall-download-limit=50K "$@"\n' "$(command -v aria2c)" >"$tmp/bin/aria2c"
printf '#!/bin/sh\nexec %s --limit-rate 25K "$@"\n' "$(command -v yt-dlp)" >"$tmp/bin/yt-dlp"
chmod +x "$tmp/bin/aria2c" "$tmp/bin/yt-dlp"
# A stand-in for /dev/location: a pipe nobody writes to blocks its reader, as the device
# does until the next update. And the system's touch, to make a log look old.
mkfifo "$tmp/location"
systouch=$(command -v touch)
PATH=$tmp/bin

fails=0
dl() { busybox ash "$here/dl" "$@"; }
b64() { printf %s "$1" | base64 | tr -d '\n'; }
check() { # check <description> <haystack> <needle>
  case $2 in *"$3"*) echo "ok    $1" ;; *) echo "FAIL  $1: wanted '$3' in:"; echo "$2"; fails=$((fails + 1)) ;; esac
}
# act <menu line>: what the Shortcut does when a line is chosen
act() { dl -a -b "$(b64 "$1")"; }
line_for() { dl -s | grep -F "$1"; }
log_of() { cat "$DL_DIR/.logs/$1.log"; }

SMALL=https://raw.githubusercontent.com/aria2/aria2/master/NEWS                                 #1
BIG=https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.xz         #2
MISSING=https://raw.githubusercontent.com/aria2/aria2/master/NOPE_404                           #3
HOSTILE='https://raw.githubusercontent.com/x/$(touch '"$tmp"'/PWNED);touch '"$tmp"'/PWNED2'    #4
MAGNET='magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Nobody+Shares+This'    #5
VIDEO_PAGE=http://127.0.0.1:$port/video.html                                                    #6
TEXT_PAGE=http://127.0.0.1:$port/text.html                                                      #7
YOUTUBE=https://www.youtube.com/watch?v=aqz-KE-bpKQ                                             #8
PLAYLIST_PAGE=http://127.0.0.1:$port/playlist.html                                              #9
STOP_PLAYLIST=http://127.0.0.1:$port/stop.html                                                  #10
SLOW_PAGE=http://127.0.0.1:$port/slow.html                                                      #11

out=$(dl -s)
check "empty list" "$out" "No downloads yet."

out=$(dl -b "$(b64 "see $SMALL!")")
check "finds a link in text and drops trailing punctuation" "$out" "Started: NEWS"
out=$(dl -b "$(printf %s "$BIG $MISSING" | busybox base64)")
check "base64 with line breaks and several links" "$out" "Started: NOPE_404"
dl -b "$(b64 "$HOSTILE")" >/dev/null
dl "$MAGNET" >/dev/null
dl "$VIDEO_PAGE" "$TEXT_PAGE" >/dev/null
out=$(dl "$YOUTUBE")
check "a YouTube link is named after the site until the title is known" "$out" "Started: youtube.com video"
out=$(dl -b "$(b64 'no links here')"); code=$?
check "says so when there is no link" "$out" "No link found"
[ "$code" = 1 ] || { echo "FAIL  exit code $code for no link"; fails=$((fails + 1)); }

sleep 8
[ ! -e "$tmp/PWNED" ] && [ ! -e "$tmp/PWNED2" ] && echo "ok    shell syntax in a link is never run" ||
  { echo "FAIL  shell syntax in a link ran"; fails=$((fails + 1)); }
for try in $(seq 20); do [ -s "$DL_SHARE/aria2-debug.txt" ] && break; sleep 1; done
check "a failed download leaves a debug report in Files" "$(cat "$DL_SHARE/aria2-debug.txt" 2>/dev/null)" "aria2 debug report · "
check "...with that download's log" "$(cat "$DL_SHARE/aria2-debug.txt" 2>/dev/null)" ": failed ("
check "a file link goes to aria2" "$(log_of 2)" "=== via aria2"
check "a magnet goes to aria2" "$(log_of 5)" "=== via aria2"
check "a web page goes to yt-dlp" "$(log_of 6)" "=== via yt-dlp"
check "a YouTube link goes to yt-dlp" "$(log_of 8)" "=== via yt-dlp"
out=$(dl -s)
check "status: finished download, with its size" "$out" "✅ NEWS · "
[ -e "$DL_SHARE/NEWS" ] && [ ! -e "$DL_DIR/NEWS" ] && echo "ok    a finished download moves to the shared folder" ||
  { echo "FAIL  NEWS wasn't moved to the shared folder"; ls "$DL_DIR" "$DL_SHARE"; fails=$((fails + 1)); }
check "status: failed download and why" "$out" "⚠️ NOPE_404 · failed: Resource not found"
check "status: aria2 progress bar, speed and time left" "$(line_for aria2-1.37.0)" "left  #2"
check "status: a magnet is preparing until it finds peers" "$out" "⏳ ▰▱▱▱▱▱▱▱▱▱ 10% preparing · looking for peers… · Nobody Shares This  #5"
check "status: video progress bar under the page's title" "$(line_for '#6')" "% · Rabbit test page"
check "status: a page without a video" "$out" "⚠️ text.html · failed: no video found on this page  #7"
check "status: yt-dlp's own error shows (YouTube is unreachable from a test machine)" "$(line_for '#8')" "· failed: "

out=$(dl "$BIG")
check "sharing a running link again" "$out" "Already downloading: aria2-1.37.0.tar.xz"
out=$(dl "${YOUTUBE}&si=FromTheShareSheet")
case $out in Started*) echo "FAIL  the same YouTube video with a si= tag became a new download: $out"; fails=$((fails + 1)) ;;
  *) echo "ok    a YouTube link's si= tag is ignored" ;; esac
[ ! -e "$DL_DIR/.logs/9.log" ] || { echo "FAIL  a 9th download was made"; fails=$((fails + 1)); }
[ -e "$DL_DIR/.logs/.updated" ] && echo "ok    tools are updated after the first download of the day" ||
  { echo "FAIL  no .updated after a download"; fails=$((fails + 1)); }
check "versions" "$(dl -v)" "Tools last updated: "
[ "$(cat "$tmp/setup-runs" 2>/dev/null)" = ran ] && echo "ok    the daily update runs the repository's setup" ||
  { echo "FAIL  setup from the repository didn't run once: $(cat "$tmp/setup-runs" 2>/dev/null)"; fails=$((fails + 1)); }
update_and_wait() {  # dl -u: the tools, then aria2 itself
  dl -u >/dev/null
  sleep 1
  for try in $(seq 60); do pgrep -f "$here/dl --update" >/dev/null || break; sleep 1; done
}
update_and_wait
[ "$(wc -l <"$tmp/setup-runs")" = 1 ] && echo "ok    an unchanged setup isn't run again" ||
  { echo "FAIL  unchanged setup ran again"; fails=$((fails + 1)); }
echo '# a newer version' >>"$tmp/www/setup.sh"
update_and_wait
[ "$(wc -l <"$tmp/setup-runs")" = 2 ] && echo "ok    a changed setup is run" ||
  { echo "FAIL  changed setup didn't run"; fails=$((fails + 1)); }
echo "Files -> On My iPhone -> Downloads -> aria2-test.shortcut" >"$DL_SHORTCUTS/.pending"
pending=$(dl -m | grep '^🆕')
check "a new shortcut is announced in the menu" "$pending" "🆕 New shortcut: Files -> On My iPhone -> Downloads -> aria2-test.shortcut."
check "tapping the announcement" "$(act "$pending")" "Done."
[ ! -e "$DL_SHORTCUTS/.pending" ] && echo "ok    the announcement goes away" ||
  { echo "FAIL  .pending still there"; fails=$((fails + 1)); }

dl "$PLAYLIST_PAGE" >/dev/null
for try in $(seq 30); do line_for '#9' | grep -q 'video 1 of 2 · [0-9]' && break; sleep 1; done
check "a playlist shows as one download, with which video it's on" "$(line_for '#9')" "video 1 of 2 · "
check "a playlist is named after the playlist" "$(line_for '#9')" "📃 Rabbit playlist  #9"

out=$(dl -m)
check "menu: downloads then actions" "$out" "#1
➕ Add link from clipboard"
check "menu: ends with close" "$out" "📲 Open iSH-AOK
❌ Close"
check "menu: update tools" "$out" "🔧 Update tools"

out=$(act "$(line_for aria2-1.37.0)")
check "tapping a running download pauses it" "$out" "Paused: aria2-1.37.0.tar.xz"
check "paused line keeps its progress" "$(line_for aria2-1.37.0)" "% · aria2-1.37.0.tar.xz · paused  #2"
out=$(act "$(line_for aria2-1.37.0)")
check "tapping it again resumes it" "$out" "Resumed: aria2-1.37.0.tar.xz"
sleep 7
check "resumed download is running" "$(line_for aria2-1.37.0)" "⬇️ "
[ -e "$DL_DIR/aria2-1.37.0.tar.xz.aria2" ] && echo "ok    resume continues from the saved point" ||
  { echo "FAIL  no aria2 control file after resume"; fails=$((fails + 1)); }

out=$(act "$(line_for '#6')")
check "pausing a video" "$out" "Paused: Rabbit test page"
ls "$DL_DIR" | grep -q 'Rabbit test page.*\.part$' && echo "ok    a paused video keeps its partial file" ||
  { echo "FAIL  no .part file for the paused video"; fails=$((fails + 1)); }
pgrep -f "Downloads.*video.html" >/dev/null && { echo "FAIL  yt-dlp still running after pause"; fails=$((fails + 1)); } ||
  echo "ok    pausing stops yt-dlp"

out=$(act "⏸ Pause all")
check "pause all" "$out" "Paused all downloads."
check "pause all: magnet paused" "$(line_for Nobody)" "⏸ Nobody Shares This · paused  #5"
out=$(act "▶️ Resume all")
# The aria2 file, the magnet, the video, the playlist, and the YouTube link if its re-share is still retrying.
case $out in "Resumed 4 download(s)." | "Resumed 5 download(s).") echo "ok    resume all" ;;
  *) echo "FAIL  resume all: $out"; fails=$((fails + 1)) ;; esac
out=$(act "✅ NEWS  #1")
check "tapping a finished download" "$out" "Already finished: NEWS"
out=$(dl "$SMALL")
check "sharing a finished link again" "$out" "Already downloaded: NEWS"
out=$(act "🔄 Refresh")
check "refresh does nothing" "[$out]" "[]"

for try in $(seq 60); do line_for '#6' | grep -q ✅ && break; sleep 1; done
check "resumed video finishes, named after its file" "$(line_for '#6')" "✅ Rabbit test page"
ls "$DL_SHARE" | grep -q '^Rabbit test page.*\.mp4$' && echo "ok    the video is saved as an mp4, in the shared folder" ||
  { echo "FAIL  no mp4 saved"; ls "$DL_DIR"; fails=$((fails + 1)); }

for try in $(seq 150); do line_for '#9' | grep -q ✅ && break; sleep 1; done
check "a finished playlist says how many videos" "$(line_for '#9')" "✅ 📃 Rabbit playlist · 2 videos · "
[ "$(ls "$DL_SHARE/Rabbit playlist" 2>/dev/null | grep -c '\.mp4$')" = 2 ] && [ ! -e "$DL_DIR/Rabbit playlist" ] &&
  echo "ok    the playlist's folder moves to the shared folder" ||
  { echo "FAIL  playlist folder not moved"; find "$DL_DIR" "$DL_SHARE"; fails=$((fails + 1)); }

# The Shortcut's screens (dl -ui): what it shows after each tap. The shortcut from before
# pictures sends no -k and gets plain lines; tap picks the line that contains $1.
ui() { dl -ui -b "$(b64 "$1")"; }
tap() { ui "$(printf '%s\n' "$screen" | grep -F -- "$1" | head -n 1)"; }
ok() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
wait_updates() {
  sleep 1
  for try in $(seq 60); do pgrep -f "$here/dl --update" >/dev/null || break; sleep 1; done
}

# A playlist to stop part-way, once its first video is in (see below).
dl "$STOP_PLAYLIST" >/dev/null

screen=$(ui @@start)
check "ui: the main menu comes first" "$(printf '%s\n' "$screen" | head -n 1)" "📥 Downloads · "
check "ui: the main menu offers the Downloads folder" "$screen" "📂 Downloads folder · Open it in Files"
check "ui: the main menu has Settings" "$screen" "⚙️ Settings · Notifications off · automatic updates"
case $screen in *'📲'* | *'🔧'* | *'❌'*) fail "ui: the main menu still has what moved to Settings: $screen" ;;
  *) ok "ui: the main menu is down to 4 rows" ;; esac
check "ui: Open the Downloads folder gives a Files link" "$(tap '📂')" "shareddocuments://$DL_SHARE"
check "ui: Add link from clipboard" "$(tap '➕')" "@@clipboard"

screen=$(tap '⚙️ Settings')
check "ui: Settings starts with Back" "$(printf '%s\n' "$screen" | head -n 1)" "⬅️ Back"
check "ui: Settings: notifications" "$screen" "🔕 Notifications · Off · tap to set up"
check "ui: Settings: aria2's own updates" "$screen" "⬆️ aria2 and its shortcut · Up to date · checked "
check "ui: Settings: the tools' updates, separately" "$screen" "🔧 Tools: yt-dlp, aria2, ffmpeg · Updated "
check "ui: Settings: open iSH-AOK" "$(tap '📲')" "@@app"
check "ui: Settings: a debug report, saved for a shortcut that can't copy" "$(tap '🐞 Save a debug report')" "ℹ️ Saved a debug report"
check "yt-dlp writes its versions and steps in the log" "$(log_of 6)" "[debug] yt-dlp version "
mkdir "$DL_DIR/.logs/.updating"
printf '=== update now\n=== step 1 Alpine packages\n=== step 2 yt-dlp\n' >"$DL_DIR/.logs/.update.log"
check "ui: a tools update shows its progress" "$(ui '')" "🔧 Tools: yt-dlp, aria2, ffmpeg · Updating · 2 of 2: yt-dlp ▰▰▰▰▰▱▱▱▱▱"
rmdir "$DL_DIR/.logs/.updating"
echo '# newer still' >>"$tmp/www/setup.sh"
screen=$(ui '')
check "ui: updating the tools" "$(tap '🔧 Tools')" "ℹ️ Updating the tools · Tap 🔧 again"
wait_updates
[ "$(wc -l <"$tmp/setup-runs")" = 2 ] && ok "updating the tools leaves dl and the shortcut alone" ||
  fail "the tools update ran the setup"
screen=$(ui '')
check "ui: checking for a new aria2" "$(tap '⬆️ aria2')" "ℹ️ Checking for a new version"
wait_updates
[ "$(wc -l <"$tmp/setup-runs")" = 3 ] && ok "...which runs the new setup" ||
  fail "aria2's update didn't run the new setup: $(cat "$tmp/setup-runs")"
screen=$(ui '')
screen=$(tap '🔁 Automatic updates')
check "ui: automatic updates can be turned off" "$screen" "🔁 Automatic updates · Off"
[ -e "$DL_DIR/.logs/.no-auto-update" ] && ok "...and they are" || fail "no .no-auto-update"
screen=$(tap '🔁 Automatic updates')
check "ui: ...and back on" "$screen" "🔁 Automatic updates · On"
check "ui: Back from Settings" "$(tap '⬅️ Back')" "📥 Downloads"

dl "$SLOW_PAGE" >/dev/null
export DL_KEEP=6
screen=$(ui @@start)
screen=$(tap '📥 Downloads')
check "ui: the list starts with Back" "$(printf '%s\n' "$screen" | head -n 1)" "⬅️ Back"
finished=$(printf '%s\n' "$screen" | grep -c -E '^(✅|⚠️) ')
[ "$finished" -le 6 ] && ok "ui: the list keeps at most 6 finished downloads" ||
  fail "ui: $finished finished downloads listed"
export DL_KEEP=1000
case $screen in *' #'[0-9]*) fail "ui: the list still shows numbers: $screen" ;; *) ok "ui: no numbers in the list" ;; esac
check "ui: a finished video, without .mp4" "$screen" "✅ Rabbit test page (1) · Downloaded · "
screen=$(tap '✅ Rabbit test page')
check "ui: tapping a finished download shows what it can do" "$screen" "▶️ Open · In the Files app
📂 Show in folder · In Files: Share
🔁 Download again · In case it was moved or deleted
🔗 Copy link · 127.0.0.1
➖ Remove from the list · The file stays where it is
🗑 Delete the file… · Asks first"
check "ui: ...under the download itself" "$screen" "✅ Rabbit test page (1) · Downloaded · 816.0K · "
check "ui: Open, for the shortcut before pictures, goes to Files" "$(tap '▶️ Open')" \
  "shareddocuments://$DL_SHARE/Rabbit%20test%20page%20%281%29.mp4"
[ "$(tap '📂 Show in folder')" = "shareddocuments://$DL_SHARE" ] && ok "ui: Show in folder opens its folder" ||
  fail "ui: Show in folder: $(tap '📂 Show in folder')"
check "ui: Copy link, for a shortcut that can't copy, shows it" "$(tap '🔗 Copy link')" "ℹ️ Its link · http://127.0.0.1:$port/video.html"
screen=$(tap '⬅️ Back')
for try in $(seq 40); do line_for '#11' | grep -q '% · ' && break; sleep 1; done
screen=$(ui '')
screen=$(tap 'Slow page')
check "ui: tapping a running download shows its screen" "$screen" "⏸ Pause · Resume it any time
⏹ Stop and delete · Deletes what it downloaded so far"
ls "$DL_DIR" | grep -q '^Slow page.*\.part$' && ok "the slow video is part-way" ||
  { fail "no partial file for the slow video"; ls "$DL_DIR"; }
screen=$(tap '⏹ Stop and delete')
check "ui: stopping says so, back on the list" "$screen" "ℹ️ Stopped Slow page"
check "ui: ...and that it deleted it" "$(printf '%s\n' "$screen" | head -n 1)" " · Deleted what it had downloaded"
printf '%s\n' "$screen" | grep -q -E '^(⬇️|⏳|⏸|✅|⚠️) Slow page' && fail "ui: the stopped download is still listed" ||
  ok "ui: the stopped download leaves the list"
ls "$DL_DIR" | grep -q '^Slow page' && { fail "stop left files behind"; ls "$DL_DIR"; } ||
  ok "stop deletes the partial files"
screen=$(tap 'Nobody Shares This')
screen=$(tap '⏹ Stop and delete')
check "ui: stopping a magnet" "$screen" "ℹ️ Stopped Nobody Shares This"

# Stopping a playlist part-way keeps the videos it finished.
for try in $(seq 120); do line_for '#10' | grep -q 'video 2 of 2 · [0-9]' && break; sleep 1; done
screen=$(ui '')
screen=$(tap 'Stop test')
check "ui: a playlist part-way offers to stop, keeping what it finished" "$screen" \
  "⏹ Stop here · Keeps the 1 finished video(s)"
screen=$(tap '⏹ Stop here')
check "ui: stopping a playlist part-way" "$screen" "ℹ️ Stopped Stop test · Kept the 1 video(s) it had finished"
check "ui: it stays on the list, as stopped" "$screen" "✅ Stop test · Stopped · 1 of 2 videos"
[ "$(ls "$DL_SHARE/Stop test" 2>/dev/null | grep -c '\.mp4$')" = 1 ] && ok "its finished video is in Files" ||
  { fail "the stopped playlist's video isn't in Files"; find "$DL_SHARE" "$DL_DIR" -name '*Stop*'; }
find "$DL_DIR" -path '*Stop test*' | grep -q . && { fail "the stopped playlist left files behind"; find "$DL_DIR" -path '*Stop test*'; } ||
  ok "the video it was on is deleted"
check "ui: Back goes to the main menu" "$(tap '⬅️ Back')" "📥 Downloads"

# The shortcut with pictures (-k <its version>) gets vCards, and taps come back as titles.
uik() { dl -ui -b "$(b64 "$1")" -k oldver0; }
cards=$(uik @@start)
check "cards: the main menu is vCards" "$(printf '%s\n' "$cards" | head -n 1)" "BEGIN:VCARD"
check "cards: a row's title" "$cards" "N;CHARSET=utf-8:Downloads;;;;"
check "cards: a row's line under the title" "$cards" "ORG;CHARSET=utf-8:Copy a link\, then tap here;"
check "cards: with a picture" "$cards" "PHOTO;ENCODING=b:iVBORw0KGgo"
[ "$(printf '%s\n' "$cards" | grep -c '^BEGIN:VCARD$')" = 4 ] && [ "$(printf '%s\n' "$cards" | grep -c '^END:VCARD$')" = 4 ] &&
  ok "cards: one vCard per row" || fail "cards: vCards don't add up: $cards"
check "cards: opening the Downloads folder" "$(uik 'Downloads folder')" "@@open:shareddocuments://$DL_SHARE"
cards=$(uik Settings)
check "cards: tapping a title" "$cards" "N;CHARSET=utf-8:Pictures in menus;;;;"
check "cards: pictures always, once iOS Settings allows it" "$(uik 'Pictures in menus')" \
  "ORG;CHARSET=utf-8:Always (iOS Settings allows it);"
check "cards: then off, as plain lines" "$(uik 'Pictures in menus')" "🖼 Pictures in menus · Off"
check "cards: ...and back on, for 10 taps a run" "$(dl -ui -b "$(b64 '🖼 Pictures in menus · Off')" -k oldver0)" \
  "ORG;CHARSET=utf-8:For 10 taps a run\, then plain;"
uik Back >/dev/null
# iOS stops the 11th row picked from menus with pictures in one run ("trying to share 11
# Contacts items"), so after 10 the menus are plain lines, which it doesn't count.
export DL_TAPS=10  # the rest of the tests tap on more than that (see the top)
uik @@start >/dev/null
for i in 1 2 3 4; do uik Settings >/dev/null; uik Back >/dev/null; done
uik Settings >/dev/null
screen=$(uik Back)
check "cards: after 10 taps in one run, plain lines" "$screen" "ℹ️ Plain menus for now · iOS allows 10 picture taps a run"
tapk() { uik "$(grep -F "$1" "$DL_DIR/.logs/.menu" | head -n 1 | cut -f 2-)"; }  # the line with $1 in it
check "...the next one too, without saying it again" "$(tapk '📥 Downloads')" "⬅️ Back"
case $(tapk '⬅️ Back') in *'Plain menus for now'*) fail "it said so again" ;; *) ok "...said once" ;; esac
check "...until the shortcut opens again" "$(uik @@start)" "BEGIN:VCARD"
for i in 1 2 3 4 5; do uik Settings >/dev/null; uik Back >/dev/null; done
check "...or iOS Settings allows more" "$(tapk '🔓 Allowed more')" "BEGIN:VCARD"
rm -f "$DL_DIR/.logs/.no-limit"
export DL_TAPS=100000
uik @@start >/dev/null
cards=$(uik Downloads)
check "cards: a finished video shows its own picture" "$cards" "PHOTO;ENCODING=b:/9j/"
check "cards: a stopped playlist" "$cards" "ORG;CHARSET=utf-8:Stopped · 1 of 2 videos"
printf 'https://example.com/x\n=== start\n=== via aria2\nFILE: %s/Hello, world; again.txt\n=== exit 0\n' "$DL_DIR" \
  >"$DL_DIR/.logs/50.log"
cards=$(uik '')
check "cards: commas and semicolons are escaped" "$cards" 'N;CHARSET=utf-8:Hello\, world\; again.txt;;;;'
printf 'hi there\n' >"$DL_DIR/Hello, world; again.txt"
cards=$(uik 'Hello, world; again.txt')
check "cards: and tapping that title finds it" "$cards" "N;CHARSET=utf-8:Hello\, world\; again.txt;;;;"
check "cards: a shortcut with pictures can play what it downloaded" "$cards" "N;CHARSET=utf-8:Open;;;;
ORG;CHARSET=utf-8:Plays it right here;"
case $cards in *'Share link'*) fail "cards: level 2 can't share, but was offered it" ;; *) ok "cards: no sharing before level 3" ;; esac
out=$(uik Open)
check "cards: Open starts the player, in Safari before level 3" "$out" "@@open:http://127.0.0.1:$DL_WEB_PORT/play/50?t="
check "...which serves the file, even from iSH-AOK's own folder" "$(curl -sL "${out#@@open:}")" "hi there"
check "cards: Delete the file asks first" "$(uik 'Delete the file…')" "N;CHARSET=utf-8:Delete Hello\, world\; again.txt?;;;;"
check "cards: No keeps it" "$(uik 'No, keep it')" "N;CHARSET=utf-8:Delete the file…;;;;"
uik 'Delete the file…' >/dev/null
check "cards: Yes deletes it" "$(uik 'Yes, delete it')" "N;CHARSET=utf-8:Deleted Hello\, world\; again.txt;;;;"
[ ! -e "$DL_DIR/Hello, world; again.txt" ] && [ ! -e "$DL_DIR/.logs/50.log" ] && ok "...the file and its place in the list" ||
  fail "the deleted file or its log is still there"

# A new shortcut from an update: setup leaves it in Files and says where in .pending.
printf 'AEA1 pretend signed shortcut' >"$DL_SHORTCUTS/aria2.shortcut"
cp "$DL_SHORTCUTS/aria2.shortcut" "$DL_SHARE/aria2.shortcut"
echo newver1 >"$DL_SHORTCUTS/.version"
echo "$DL_SHARE/aria2.shortcut" >"$DL_SHORTCUTS/.pending"
check "ui: the old shortcut opens the new one in Files when it opens" "$(ui @@start)" "shareddocuments://$DL_SHARE/aria2.shortcut"
screen=$(ui @@start)
check "ui: just once; then the main menu offers it" "$(printf '%s\n' "$screen" | head -n 1)" "🆕 New aria2 shortcut · Tap to install it, then tap Replace"
check "ui: tapping that opens it again" "$(tap '🆕')" "shareddocuments://$DL_SHARE/aria2.shortcut"
uik '' >/dev/null
check "cards: a shortcut with pictures imports the new one itself" "$(uik 'New aria2 shortcut')" "@@import"
check "dl --shortcut prints it" "$(dl --shortcut | base64 -d)" "AEA1 pretend signed shortcut"
out=$(dl -ui -b "$(b64 @@start)" -k newver1)
case $out in *'New aria2 shortcut'*) fail "the new shortcut is offered to itself" ;;
  *) ok "once the new shortcut runs, it's no longer offered" ;; esac
[ ! -e "$DL_SHORTCUTS/.pending" ] && ok "...and .pending is gone" || fail ".pending still there"

# A shortcut of level 3 shows pages in a sheet (the live view, the player), and copies and
# shares links.
u3() { dl -ui -b "$(b64 "$1")" -k 3-test; }
AGAIN=http://127.0.0.1:$port/again.txt
printf 'first\n' >"$tmp/www/again.txt"
printf 'second\n' >"$tmp/www/note2.txt"
dl "$AGAIN" >/dev/null
dl "http://127.0.0.1:$port/rabbit3.mp4" >/dev/null  # about 16 s at 50K/s: something to watch
dl "http://127.0.0.1:$port/gone.mp4" >/dev/null     # fails: something to report
for try in $(seq 30); do line_for again.txt | grep -q ✅ && break; sleep 1; done
u3 @@start >/dev/null
cards=$(u3 Downloads)
check "level 3: the list offers the live view while something downloads" "$cards" "N;CHARSET=utf-8:Watch live;;;;"
out=$(u3 'Watch live')
check "level 3: the live view opens in a sheet" "$out" "@@web:http://127.0.0.1:$DL_WEB_PORT/?t="
live=${out#@@web:}
token=${live#*t=}
web() { curl -s "http://127.0.0.1:$DL_WEB_PORT$1"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
check "the live view's page" "$(curl -s "$live")" "<title>aria2</title>"
check "its status says what's downloading" "$(web "/status?t=$token")" '"title": "rabbit3.mp4", "state": "running"'
[ "$(code "http://127.0.0.1:$DL_WEB_PORT/status")" = 403 ] && ok "...but only with its token" || fail "the live view answered without its token"
[ "$(code -H 'Host: example.com' "http://127.0.0.1:$DL_WEB_PORT/status?t=$token")" = 403 ] && ok "...and only to 127.0.0.1" ||
  fail "the live view answered another host name"
check "the player shows a playlist's videos" "$(web "/play/9?t=$token")" "Rabbit playlist</h1><ul><li><a href=\"/play/9?t=$token&f="
check "the player plays a video" "$(web "/play/6?t=$token")" "<video src=\"/file/6?t=$token\""
check "...in ranges, as Safari asks for them" "$(curl -s -D - -o /dev/null -r 100-199 "http://127.0.0.1:$DL_WEB_PORT/file/6?t=$token" | tr -d '\r')" \
  "Content-Range: bytes 100-199/$(wc -c <"$tmp/www/rabbit.mp4" | tr -d ' ')"
post() { curl -s -H "X-Token: $token" -H 'Content-Type: application/json' -d "$2" "http://127.0.0.1:$DL_WEB_PORT$1"; }
rid=$(line_for rabbit3 | sed 's/.*#//')
check "the live view's Pause button" "$(post /act "{\"id\": $rid, \"do\": \"pause\"}")" '"message": "Paused rabbit3.mp4"'
check "...pauses it" "$(line_for rabbit3)" " · paused  #$rid"
check "its Resume button" "$(post /act "{\"id\": $rid, \"do\": \"resume\"}")" '"message": "Resumed rabbit3.mp4"'
check "pasting a link into it" "$(post /add "{\"text\": \"http://127.0.0.1:$port/note2.txt\"}")" '"message": "Started: note2.txt"'

cards=$(u3 'again.txt')
check "level 3: a finished download can share its link" "$cards" "N;CHARSET=utf-8:Share link;;;;"
aid=$(line_for again.txt | sed 's/.*#//')
out=$(u3 Open)
check "level 3: Open plays it in a sheet" "$out" "@@web:http://127.0.0.1:$DL_WEB_PORT/play/$aid?t=$token"
[ "$(code "${out#@@web:}")" = 303 ] && ok "a text file opens as itself" || fail "the player didn't hand over the text file"
check "...from Files" "$(curl -sL "${out#@@web:}")" "first"
check "level 3: Copy link" "$(u3 'Copy link')" "@@copy:$AGAIN"
check "...and says so" "$(u3 '')" "N;CHARSET=utf-8:Copied the link;;;;"
check "level 3: Share link" "$(u3 'Share link')" "@@share:$AGAIN"
check "Download again" "$(u3 'Download again')" "N;CHARSET=utf-8:Downloading it again;;;;"
for try in $(seq 30); do line_for again.txt | grep -q ✅ && break; sleep 1; done
[ "$(ls "$DL_SHARE" | grep -c '^again')" = 1 ] && [ ! -e "$DL_DIR/again.txt" ] &&
  ok "downloading the same file again keeps one copy of it" || fail "after Download again: $(ls "$DL_SHARE" "$DL_DIR")"
printf 'second, and longer\n' >"$tmp/www/again.txt"
u3 '' >/dev/null
u3 'again.txt' >/dev/null
u3 'Download again' >/dev/null
for try in $(seq 30); do line_for 'again (2).txt' | grep -q ✅ && break; sleep 1; done
[ "$(cat "$DL_SHARE/again (2).txt" 2>/dev/null)" = "second, and longer" ] && [ "$(cat "$DL_SHARE/again.txt")" = first ] &&
  ok "a different file of the same name gets a name of its own" || fail "after Download again of a changed file: $(ls "$DL_SHARE")"
u3 '' >/dev/null
u3 'again (2).txt' >/dev/null
check "level 3: deleting a file in Files asks first" "$(u3 'Delete the file…')" "N;CHARSET=utf-8:Delete again (2).txt?;;;;"
check "...then deletes it" "$(u3 'Yes, delete it')" "N;CHARSET=utf-8:Deleted again (2).txt;;;;"
[ ! -e "$DL_SHARE/again (2).txt" ] && [ -e "$DL_SHARE/again.txt" ] && ok "...and only that file" ||
  fail "deleting went wrong: $(ls "$DL_SHARE")"
for try in $(seq 30); do line_for gone.mp4 | grep -q ⚠️ && break; sleep 1; done
gid=$(line_for gone.mp4 | sed 's/.*#//')
u3 '' >/dev/null
cards=$(u3 'gone.mp4')
check "level 3: a failed download offers a debug report" "$cards" "N;CHARSET=utf-8:Copy a debug report;;;;"
out=$(u3 'Copy a debug report')
check "...which is copied" "$(printf '%s\n' "$out" | head -n 1)" "@@copy:aria2 debug report · "
check "...with its log" "$out" "== Download #$gid: failed"
check "...and its settings, but not the Bark key or the live view's token" "$out" "Settings: notifications "
case $out in *GOODKEY42* | *"$token"*) fail "the report gave away a secret" ;; *) ok "the report keeps secrets out" ;; esac
check "...then says so" "$(u3 '')" "N;CHARSET=utf-8:Copied a debug report;;;;"
check "the live view shows the report, ready to copy" "$(web "/report/$gid?t=$token")" "Copy the report</button>"
check "...the same report" "$(web "/report/$gid?t=$token")" "== Download #$gid: failed"

# A long screen of vCards comes in pages: iOS lets a shortcut hand at most 10 contacts at
# a time to iSH-AOK, unless the phone allows "large amounts of data".
for i in 70 71 72 73 74 75 76 77 78 79; do
  printf 'https://example.com/page-%s.zip\n=== start\n=== via aria2\n' $i >"$DL_DIR/.logs/$i.log"  # paused
done
u3 @@start >/dev/null
cards=$(u3 Downloads)
[ "$(printf '%s\n' "$cards" | grep -c '^BEGIN:VCARD$')" -le 10 ] && ok "cards: a long list comes in pages of at most 10 rows" ||
  fail "cards: $(printf '%s\n' "$cards" | grep -c '^BEGIN:VCARD$') rows on one screen"
check "...with More at the bottom" "$cards" "N;CHARSET=utf-8:More;;;;"
cards=$(u3 More)
check "...which shows the next page" "$cards" "N;CHARSET=utf-8:Previous;;;;"
[ "$(printf '%s\n' "$cards" | grep -c '^BEGIN:VCARD$')" -le 10 ] && ok "...of at most 10 rows too" || fail "page 2 is too long"
check "...and Previous goes back" "$(u3 Previous)" "N;CHARSET=utf-8:Back;;;;"
[ "$(ui '' | wc -l)" -gt 10 ] && ok "plain lines aren't paged: they're text, not contacts" || fail "plain lines were paged"
for i in 70 71 72 73 74 75 76 77 78 79; do rm -f "$DL_DIR/.logs/$i.log"; done

# A download that prints nothing for 5 minutes was frozen with iSH-AOK: it starts again.
printf 'resumed\n' >"$tmp/www/stall.txt"
nohup sh -c 'sleep 900' sh --work 80 >/dev/null 2>&1 &
echo $! >"$DL_DIR/.logs/80.pid"
printf 'http://127.0.0.1:%s/stall.txt\n=== start\n=== via aria2\n[#e5d549 4KiB/1.6MiB(1%%) CN:1 DL:0B]\n' "$port" \
  >"$DL_DIR/.logs/80.log"
"$systouch" -d '10 minutes ago' "$DL_DIR/.logs/80.log"
u3 @@start >/dev/null
check "a download quiet for 5 minutes is started again" "$(log_of 80)" "=== stalled: nothing for 5 minutes, so it starts again"
for try in $(seq 20); do line_for stall.txt | grep -q ✅ && break; sleep 1; done
check "...and carries on" "$(line_for stall.txt)" "✅ stall.txt"
# Not while ffmpeg merges, which yt-dlp -v follows with its command line.
nohup sh -c 'sleep 900' sh --work 81 >/dev/null 2>&1 &
echo $! >"$DL_DIR/.logs/81.pid"
printf 'http://127.0.0.1:%s/merge.html\n=== start\n=== via yt-dlp\n[Merger] Merging formats into "x.mp4"\n[debug] ffmpeg command line: ffmpeg -i x\n' \
  "$port" >"$DL_DIR/.logs/81.log"
"$systouch" -d '10 minutes ago' "$DL_DIR/.logs/81.log"
u3 @@start >/dev/null
case $(log_of 81) in *'=== stalled'*) fail "a merge was taken for a stalled download" ;; *) ok "...but not one that's merging" ;; esac
kill "$(cat "$DL_DIR/.logs/81.pid")" 2>/dev/null
rm -f "$DL_DIR/.logs/81.log" "$DL_DIR/.logs/81.pid"

# Resume twice (a double tap in the live view) is one worker, not two on the same file.
printf 'http://127.0.0.1:%s/stall.txt?twice\n=== start\n=== via aria2\n=== paused\n=== exit 143\n' "$port" >"$DL_DIR/.logs/82.log"
nohup sh -c 'sleep 900' sh --work 82 >/dev/null 2>&1 &
echo $! >"$DL_DIR/.logs/82.pid"
dl --act 82 resume >/dev/null
[ "$(grep -c '^=== start' "$DL_DIR/.logs/82.log")" = 1 ] && ok "resuming a running download doesn't start it twice" ||
  fail "resume started a second worker: $(log_of 82)"
kill "$(cat "$DL_DIR/.logs/82.pid")" 2>/dev/null
rm -f "$DL_DIR/.logs/82.log" "$DL_DIR/.logs/82.pid"

# Stop deletes what earlier starts left too (paused at 60%, resumed, then stopped).
printf 'http://127.0.0.1:%s/two.html\n=== start\n=== via yt-dlp\n[download] Destination: %s/Two.mp4\n=== paused\n=== exit 143\n=== start\n=== via yt-dlp\n=== paused\n=== exit 143\n' \
  "$port" "$DL_DIR" >"$DL_DIR/.logs/83.log"
printf 'part\n' >"$DL_DIR/Two.mp4.part"
dl --act 83 stop >/dev/null
[ ! -e "$DL_DIR/Two.mp4.part" ] && ok "stop deletes what an earlier start left" || fail "Two.mp4.part is still there"

# A folder whose name starts with "-" moves to Files like any other.
mkdir -p "$DL_DIR/- Best of -"
printf 'one\n' >"$DL_DIR/- Best of -/One.mp4"
printf 'http://127.0.0.1:%s/best.html\n=== start\n=== via yt-dlp\nFILE: %s/- Best of -/One.mp4\n=== exit 0\n' "$port" "$DL_DIR" \
  >"$DL_DIR/.logs/84.log"
dl --deliver 84 >>"$DL_DIR/.logs/84.log"
[ -e "$DL_SHARE/- Best of -/One.mp4" ] && ok "a folder named \"- …\" moves to Files" || fail "the - folder wasn't moved: $(log_of 84)"
rm -f "$DL_DIR/.logs/84.log"

# While something downloads, a loop keeps reading the location (and so iSH-AOK running).
# BusyBox dd rewrites its arguments, so its command line reads "dd if <file>".
export DL_LOCATION="$tmp/location"
reader="dd if[= ]$tmp/location"
dl "http://127.0.0.1:$port/rabbit2.mp4?awake" >/dev/null
for try in $(seq 10); do pgrep -f "$reader" >/dev/null && break; sleep 1; done
pgrep -f '^sh [^ ]*dl --awake-loop$' >/dev/null && ok "a download starts the loop that keeps iSH-AOK awake" ||
  fail "no awake loop while downloading"
[ "$(pgrep -f "$reader" | wc -l)" = 1 ] && ok "...which reads the location, once" || fail "readers: $(pgrep -f "$reader" | wc -l)"
dl "http://127.0.0.1:$port/rabbit3.mp4?awake" >/dev/null
sleep 2
loops() {  # one process group each: the loop's own forks (for sleep, say) are in its group
  for p in $(pgrep -f '^sh [^ ]*dl --awake-loop$'); do cut -d' ' -f5 "/proc/$p/stat" 2>/dev/null; done | sort -u | wc -l
}
[ "$(loops)" = 1 ] && ok "...one loop however many downloads" || fail "$(loops) awake loops"
dl -p >/dev/null
for try in $(seq 15); do [ "$(loops)" = 0 ] && break; sleep 1; done
[ "$(loops)" = 0 ] && ok "...and stops when nothing downloads" || fail "the awake loop kept going with nothing downloading"
pgrep -f "$reader" >/dev/null && fail "something still reads the location" || ok "...reader and all"
unset DL_LOCATION

# formats.py: a video's qualities, from what yt-dlp -J prints (here, a made-up YouTube-like one).
rows=$(python3 "$DL_FORMATS" "$here/test-data/youtube-like.json" | tr '\037' '|')
check "formats.py: one row a resolution, H.264 first" "$rows" "video|137|1080p|H.264 · 114 MB · plays everywhere · sound next|0"
check "...the best of the rest where there's no H.264" "$rows" "video|313|2160p|VP9 · 858 MB · may not play in Files · sound next|0"
check "...a format with its own sound says so" "$rows" "video|18|360p|H.264 · 8.6 MB · plays everywhere · with sound|1"
check "...then the sounds, AAC first" "$(printf '%s\n' "$rows" | grep '^audio' | head -n 1)" "audio|140|AAC · 130 kbps|3.3 MB · plays everywhere"
case $rows in *140-drc* | *storyboard* | *sb0*) fail "formats.py lists formats nobody wants: $rows" ;;
  *) ok "...without DRC copies or storyboards" ;; esac
check "formats.py: a playlist" "$(python3 "$DL_FORMATS" "$here/test-data/playlist.json" | tr '\037' '|')" "playlist|12"
# X has each height twice: HLS without sound, and an MP4 with it (and no codec named).
rows=$(python3 "$DL_FORMATS" "$here/test-data/x-like.json" | tr '\037' '|')
check "formats.py: the MP4 with its sound in it, rather than one that needs a sound added" "$rows" \
  "video|http-2176|1080p|plays everywhere · with sound|1"
case $rows in *hls-2176* | *hls-832*) fail "formats.py offered X's silent HLS videos too: $rows" ;;
  *) ok "...one row a height" ;; esac
check "...and X's sounds" "$rows" "audio|hls-audio-128000-Audio|AAC · 128 kbps|plays everywhere"

# A shortcut of level 4 asks how to download a shared video: quickly, by the rule in
# Settings, or in a quality picked from what the site has.
u4() { dl -ui -b "$(b64 "$1")" -k 4-test; }
check "level 4: a shared file starts at once, with a notification" "$(u4 "@@add:http://127.0.0.1:$port/note3.txt")" \
  "@@notify:Started: note3.txt"
cards=$(u4 "@@add:Look at this: http://127.0.0.1:$port/quality.html")
check "level 4: a shared video page asks how to download it" "$cards" "N;CHARSET=utf-8:Quick download;;;;
ORG;CHARSET=utf-8:Best for iPhone · H.264 up to 1080p: plays everywhere;"
check "...or to choose the quality" "$cards" "N;CHARSET=utf-8:Choose the quality;;;;"
check "...or to get just its sound" "$cards" "N;CHARSET=utf-8:Audio only;;;;"
cards=$(u4 'Choose the quality')
check "Choose the quality lists what the site has" "$cards" "N;CHARSET=utf-8:mp4;;;;
ORG;CHARSET=utf-8:plays everywhere · with sound;"
check "...under the video's title" "$cards" "N;CHARSET=utf-8:Quality test (1);;;;"
qid=$(($(ls "$DL_DIR/.logs" | sed -n 's/^\([0-9]*\)\.log$/\1/p' | sort -n | tail -n 1) + 1))
check "picking one starts it, then closes with a notification" "$(u4 mp4)" "@@notify:Started: Quality test (1)"
case $(sed -n 1p "$DL_DIR/.logs/$qid.fmt" 2>/dev/null) in 0/*) ok "...in the format picked" ;; *) false ;; esac || fail "no format kept for #$qid"
for try in $(seq 20); do grep -q 'Command-line config' "$DL_DIR/.logs/$qid.log" 2>/dev/null && break; sleep 1; done
check "...from what yt-dlp already found, without finding it again" "$(log_of $qid)" "'--load-info-json', '$DL_DIR/.logs/$qid.info.json'"

cards=$(u4 "@@paste:http://127.0.0.1:$port/audio.html")
check "level 4: a pasted video page asks too" "$cards" "N;CHARSET=utf-8:Audio only;;;;"
aud=$(($(ls "$DL_DIR/.logs" | sed -n 's/^\([0-9]*\)\.log$/\1/p' | sort -n | tail -n 1) + 1))
check "Audio only, from the menu, goes back to the list" "$(u4 'Audio only')" "N;CHARSET=utf-8:Started: audio.html;;;;"
[ "$(sed -n 2p "$DL_DIR/.logs/$aud.fmt" 2>/dev/null)" = audio ] && ok "...for the sound only" || fail "no audio format for #$aud"
for try in $(seq 20); do grep -q 'Command-line config' "$DL_DIR/.logs/$aud.log" 2>/dev/null && break; sleep 1; done
check "...made into M4A" "$(log_of $aud)" "'-x', '--audio-format', 'm4a'"

cards=$(u4 "@@add:http://127.0.0.1:$port/list2.html")
cards=$(u4 'Choose the quality')
check "level 4: a playlist offers one quality for all its videos" "$cards" "N;CHARSET=utf-8:Second playlist;;;;
ORG;CHARSET=utf-8:2 videos: pick a quality for all of them;"
check "...from the rules" "$cards" "N;CHARSET=utf-8:480p;;;;"
check "...and Back goes back" "$(u4 Back)" "N;CHARSET=utf-8:Choose the quality;;;;"
[ "$(u4 Cancel)" = @@exit ] && ok "Cancel, from the share sheet, closes" || fail "Cancel didn't close"
[ ! -e "$DL_DIR/.logs/.choice" ] && ok "...and forgets the choice" || fail ".choice is still there"

# Only what the site has: one quality is nothing to choose from.
u4 "@@add:http://127.0.0.1:$port/quality.html?one" >/dev/null
u4 'Choose the quality' >/dev/null
cards=$(u4 Back)
case $cards in *'N;CHARSET=utf-8:Choose the quality;'*) fail "Choose the quality offered with one quality: $cards" ;;
  *) ok "a video with one quality doesn't offer to choose it" ;; esac
check "...but a quick download still" "$cards" "N;CHARSET=utf-8:Quick download;;;;"
u4 Cancel >/dev/null
# A video without its sound, where the site has only one sound: no need to ask which.
mkdir -p "$DL_DIR/.logs/.choice"
printf '%s\n' "http://127.0.0.1:$port/quality.html?sound" >"$DL_DIR/.logs/.choice/link"
echo share >"$DL_DIR/.logs/.choice/from"
printf 'title\037One sound\nvideo\037v1\037720p\037H.264 · sound next\0370\naudio\037a1\037AAC · 128 kbps\037plays everywhere\n' \
  >"$DL_DIR/.logs/.choice/rows"
: >"$DL_DIR/.logs/.choice/done"
one=$(($(ls "$DL_DIR/.logs" | sed -n 's/^\([0-9]*\)\.log$/\1/p' | sort -n | tail -n 1) + 1))
check "a video picked without its sound gets the only sound there is" "$(u4 "@@again:v:v1:0")" "@@notify:Started: One sound"
case $(sed -n 1p "$DL_DIR/.logs/$one.fmt" 2>/dev/null) in v1+a1/*) ok "...in one go" ;;
  *) fail "#$one's format: $(cat "$DL_DIR/.logs/$one.fmt" 2>/dev/null)" ;; esac

# Level 5: iOS stops a Run Command that takes long in the background ("an unknown error"),
# so one waits only a little for the qualities, then the shortcut runs dl again by itself.
u5() { dl -ui -b "$(b64 "$1")" -k 5-test; }
printf '%s\n' 'import runpy, sys, time' 'time.sleep(4)' "sys.argv = ['$DL_FORMATS'] + sys.argv[1:]" \
  "runpy.run_path('$DL_FORMATS', run_name='__main__')" >"$tmp/slow-formats.py"
DL_FORMATS=$tmp/slow-formats.py u5 "@@add:http://127.0.0.1:$port/quality.html?slow" >/dev/null
[ -s "$DL_DIR/.logs/.choice/pid" ] && ok "level 5: the qualities are looked for as soon as it asks" ||
  fail "nothing looks for the qualities"
check "...a Run Command waits only a little, then asks to be run again" "$(DL_WAIT=1 u5 'Choose the quality')" \
  "@@again:pick"
check "...a level 4 shortcut says it's still looking" "$(DL_WAIT=1 u4 'Choose the quality')" \
  "N;CHARSET=utf-8:Still finding the qualities…;;;;"
check "...and once they're known, they're shown" "$(u5 @@again:pick)" "N;CHARSET=utf-8:mp4;;;;"
u5 Back >/dev/null
[ "$(u5 Cancel)" = @@exit ] && ok "...Cancel closes" || fail "Cancel didn't close"
DL_FORMATS=$tmp/slow-formats.py u5 "@@add:http://127.0.0.1:$port/quality.html?cancel" >/dev/null
probe=$(cat "$DL_DIR/.logs/.choice/pid" 2>/dev/null)
u5 Cancel >/dev/null
sleep 1
case $(cut -d' ' -f3 "/proc/$probe/stat" 2>/dev/null) in
  '' | Z) ok "...and stops looking for the qualities" ;;
  *) fail "Cancel left the search for qualities running (pid $probe)" ;;
esac

# Sharing a video again while it downloads carries that one on, rather than starting a
# second download into the same files.
u5 "@@add:$SLOW_PAGE?twice" >/dev/null
twice=$(($(ls "$DL_DIR/.logs" | sed -n 's/^\([0-9]*\)\.log$/\1/p' | sort -n | tail -n 1) + 1))
check "a video shared and downloading..." "$(u5 'Quick download')" "@@notify:Started"
check "...shared again, isn't started twice" "$(u5 "@@add:$SLOW_PAGE?twice")" "@@notify:Already downloading"
dl --act "$twice" pause >/dev/null

# iSH-AOK keeps names escaped, so a non-English title fills its 255 bytes 3 times as fast.
# A name the disk refuses ([Errno 36]) starts again, named after the video's id. Here a
# title six times over is what's too long.
long=$(($(ls "$DL_DIR/.logs" | sed -n 's/^\([0-9]*\)\.log$/\1/p' | sort -n | tail -n 1) + 1))
DL_TITLE='%(title)s%(title)s%(title)s%(title)s%(title)s%(title)s' dl "http://127.0.0.1:$port/long.html" >/dev/null
for try in $(seq 90); do line_for "#$long" | grep -q '✅\|⚠️' && break; sleep 1; done
check "a name too long for the disk starts again with a short one" "$(log_of $long)" \
  "=== the name is too long for iSH-AOK, so it starts again with a shorter one"
check "...and finishes" "$(line_for "#$long")" "✅"
ls "$DL_SHARE" | grep -q '^long[-0-9]*\.mp4$' && ok "...named after the video's id" ||
  fail "no long.mp4 among: $(ls "$DL_SHARE")"
# The reason given is the one that caused it, and the report keeps one traceback of many.
mkdir -p "$tmp/tb"
{ echo "http://127.0.0.1:$port/never.html"; echo "=== start"; echo "=== via yt-dlp"
  for frag in 23 24; do
    echo "ERROR: unable to open for writing: [Errno 36] Filename too long: 'x.part-Frag$frag.part'"
    printf 'Traceback (most recent call last):\n  File "a.py", line 1\n    open(name)\n'
    echo "OSError: [Errno 36] Filename too long: 'x.part-Frag$frag.part'"
  done
  echo "ERROR: The downloaded file is empty"; echo '  File "<frozen runpy>", line 203'; echo "=== exit 1"
} >"$DL_DIR/.logs/999.log"
check "a failure says why, not just that the file came out empty" "$(line_for '#999')" \
  "failed: the name was too long for iSH-AOK"
report=$(dl --report 999)
[ "$(printf '%s\n' "$report" | grep -c '^Traceback')" = 1 ] && ok "...and the report keeps one traceback" ||
  fail "the report's tracebacks: $(printf '%s\n' "$report" | grep -c '^Traceback')"
check "...with every error line" "$report" "Filename too long: 'x.part-Frag24.part'"
rm -f "$DL_DIR/.logs/999.log"

u4 @@start >/dev/null
u4 Settings >/dev/null
cards=$(u4 'Quick download')
check "Settings: the quick download's rules" "$cards" "N;CHARSET=utf-8:Best for iPhone;;;;
ORG;CHARSET=utf-8:H.264 up to 1080p: plays everywhere;"
check "...the one in use is ticked" "$cards" "PHOTO;ENCODING=b:$(cat "$DL_ICONS/done.b64")"
cards=$(u4 720p)
[ "$(cat "$DL_DIR/.logs/.quality")" = 720 ] && ok "...picking another uses it" || fail "the rule wasn't set"
cards=$(u4 'Ask when sharing a video · On')
check "...and asking can be turned off" "$cards" "N;CHARSET=utf-8:Ask when sharing a video · Off;;;;"
check "then a shared video starts at once" "$(u4 "@@add:http://127.0.0.1:$port/text.html?again")" "@@notify:Started: "
u4 'Ask when sharing a video · Off' >/dev/null
u4 'Best for iPhone' >/dev/null
[ ! -e "$DL_DIR/.logs/.no-ask" ] && [ "$(cat "$DL_DIR/.logs/.quality")" = iphone ] && ok "...and back" || fail "settings not restored"

# Notifications, through the stand-in for Bark's server.
[ ! -e "$tmp/bark.log" ] && ok "no notifications before they're turned on" ||
  fail "notifications were sent while they were off"
screen=$(ui @@start)
screen=$(tap '⚙️ Settings')
screen=$(tap '🔕 Notifications')
check "ui: the notifications screen says how to turn them on" "$screen" "2️⃣ In Bark, copy a link"
check "ui: 3️⃣ reads the clipboard" "$(tap '3️⃣')" "@@clipboard"
before=$(ls "$DL_DIR/.logs" | grep -c '\.log$')
out=$(dl -b "$(b64 "$SMALL?copied-by-mistake")")
check "after 3️⃣, the clipboard has to have a Bark link" "$out" "There's no Bark link on the clipboard."
[ "$(ls "$DL_DIR/.logs" | grep -c '\.log$')" = "$before" ] && ok "...and anything else on it isn't downloaded" ||
  fail "after 3️⃣, the clipboard's link was downloaded"
out=$(dl -b "$(b64 "$DL_BARK/WRONGKEY/Push content")")
check "a Bark link that Bark doesn't take" "$out" "Bark didn't take that link, so notifications are still off."
out=$(dl -b "$(b64 "Copied from Bark: $DL_BARK/GOODKEY42/Push%20content")")
check "a Bark link turns notifications on" "$out" "Notifications are on. Bark just sent you a test one."
check "...and sends a test notification" "$(cat "$tmp/bark.log")" '"title": "🔔 aria2 notifications are on"'
screen=$(ui '')
check "ui: the notifications screen once they're on" "$screen" "🔔 Send a test notification
🔕 Turn off notifications"
check "ui: sending a test notification" "$(tap '🔔 Send')" "ℹ️ Sent a test notification"
check "...which opens the Downloads folder when tapped" "$(tail -n 1 "$tmp/bark.log")" "\"url\": \"shareddocuments://$DL_SHARE\""
screen=$(tap '⬅️ Back')
check "ui: Settings says they're on" "$screen" "🔔 Notifications · On: one when a download finishes"
check "ui: so does the main menu" "$(tap '⬅️ Back')" "⚙️ Settings · Notifications on"
check "cards: Get Bark opens the App Store" "$(dl -ui -b "$(b64 '')" -k oldver0 >/dev/null; dl -ui -b "$(b64 Settings)" -k oldver0 >/dev/null; mv "$DL_DIR/.logs/.bark" "$DL_DIR/.logs/.bark.keep"; dl -ui -b "$(b64 Notifications)" -k oldver0 >/dev/null; dl -ui -b "$(b64 'Get Bark')" -k oldver0)" \
  "@@open:https://apps.apple.com/app/bark-custom-notifications/id1403753865"
mv "$DL_DIR/.logs/.bark.keep" "$DL_DIR/.logs/.bark"

printf 'hello\n' >"$tmp/www/note.txt"
printf 'hello\n' >"$tmp/www/say\"hi\".txt"
dl "http://127.0.0.1:$port/note.txt" "http://127.0.0.1:$port/say%22hi%22.txt" "http://127.0.0.1:$port/missing.zip" >/dev/null
notified() { grep -F -- "$1" "$tmp/bark.log"; }
for try in $(seq 60); do
  notified note.txt >/dev/null && notified 'say\"hi\"' >/dev/null && notified missing.zip >/dev/null && break
  sleep 1
done
check "a finished download sends a notification" "$(notified note.txt)" '"body": "note.txt · '
check "...saying it's downloaded" "$(notified note.txt)" '"title": "✅ Downloaded"'
check "...which opens the file when tapped" "$(notified note.txt)" "\"url\": \"shareddocuments://$DL_SHARE/note.txt\""
check "a name with quotes in it" "$(notified say)" '"body": "say\"hi\".txt · '
check "a failed download sends a notification" "$(notified missing.zip)" '"title": "⚠️ Download failed"'
grep -q '^NOT JSON' "$tmp/bark.log" && fail "a notification wasn't valid JSON" || ok "every notification is valid JSON"

screen=$(ui @@start)
screen=$(tap '⚙️ Settings')
screen=$(tap '🔔 Notifications')
screen=$(tap '🔕')
check "ui: turning notifications off" "$screen" "ℹ️ Notifications are off"
[ ! -e "$DL_DIR/.logs/.bark" ] && ok "...and they are" || fail ".bark still there"
screen=$(tap '🔔 Turn notifications back on')
check "ui: turning them back on" "$screen" "🔕 Turn off notifications"
screen=$(tap '🔕')
check "ui: Back from notifications goes to Settings" "$(tap '⬅️ Back')" "🔕 Notifications · Off · tap to set up"

dl -p >/dev/null
out=$(act "🧹 Clear finished")
check "clear finished" "$out" "finished download(s)
The files are still in Downloads"
out=$(dl -s)
case $out in *NEWS* | *NOPE_404* | *Rabbit*) fail "cleared downloads still listed" ;;
  *) ok "cleared downloads leave the list" ;; esac
[ -e "$DL_SHARE/NEWS" ] && ok "clearing keeps the files" || fail "NEWS was deleted"
ls "$DL_DIR/.logs" | grep -q '\.thumb$' && fail "pictures of cleared downloads are left behind" || ok "clearing removes their pictures"

# The list keeps only the newest finished downloads, from the main menu too (shares from
# the share sheet may never open the list).
DL_KEEP=2 dl -ui -b "$(b64 @@start)" -k 5-test >/dev/null
finished=0
for f in "$DL_DIR"/.logs/[0-9]*.log; do grep -q '^=== exit 0' "$f" && finished=$((finished + 1)); done
[ "$finished" -le 3 ] && ok "the main menu keeps the list short" || fail "$finished finished downloads still listed"
find "$DL_SHARE" -name '.*.moving' | grep -q . && fail "half-moved files were left in Files" ||
  ok "nothing was left half-moved in Files"

[ "$fails" = 0 ] && echo "All checks passed." || { echo "$fails check(s) failed."; exit 1; }
