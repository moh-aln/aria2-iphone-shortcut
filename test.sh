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
for tool in busybox sh awk base64 cat cp cut date dd du find grep head ls mkdir mv od rm rmdir sed seq setsid sha256sum sleep sort stat tail timeout tr wc; do
  ln -s "$(command -v busybox)" "$tmp/bin/$tool"
done
for tool in nohup pgrep pkill kill curl ffmpeg python3; do ln -s "$(command -v $tool)" "$tmp/bin/$tool"; done
# The live view's server, from this folder, on a port of its own.
export DL_WEB="$here/web.py" DL_WEB_PORT=18781
# The menus' pictures, as setup installs them.
export DL_ICONS="$tmp/icons"
mkdir "$DL_ICONS"
for f in "$here"/icons/*.png; do name=${f##*/}; base64 -w 0 "$f" >"$DL_ICONS/${name%.png}.b64"; done
printf '#!/bin/sh\nexec %s --max-overall-download-limit=50K "$@"\n' "$(command -v aria2c)" >"$tmp/bin/aria2c"
printf '#!/bin/sh\nexec %s --limit-rate 25K "$@"\n' "$(command -v yt-dlp)" >"$tmp/bin/yt-dlp"
chmod +x "$tmp/bin/aria2c" "$tmp/bin/yt-dlp"
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
screen=$(ui @@start)
screen=$(tap '📥 Downloads')
check "ui: the list starts with Back" "$(printf '%s\n' "$screen" | head -n 1)" "⬅️ Back"
finished=$(printf '%s\n' "$screen" | grep -c -E '^(✅|⚠️) ')
[ "$finished" -le 6 ] && ok "ui: the list keeps at most 6 finished downloads" ||
  fail "ui: $finished finished downloads listed"
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
check "cards: the plain lines' setting is there too" "$(uik 'Pictures in menus')" "🖼 Pictures in menus · Off"
check "cards: ...and turns back on" "$(dl -ui -b "$(b64 '🖼 Pictures in menus · Off')" -k oldver0)" "N;CHARSET=utf-8:Pictures in menus;;;;"
uik Back >/dev/null
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

[ "$fails" = 0 ] && echo "All checks passed." || { echo "$fails check(s) failed."; exit 1; }
