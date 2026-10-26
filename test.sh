#!/bin/sh
# Checks dl on a computer, the way the iPhone runs it: BusyBox ash and BusyBox's text tools,
# links base64-encoded. Needs aria2c, yt-dlp, busybox, curl, python3 (for a local web page
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
printf '<!doctype html><title>Rabbit test page</title><video src="rabbit.mp4"></video>\n' >"$tmp/www/video.html"
printf '<!doctype html><title>Just text</title><p>No video here.</p>\n' >"$tmp/www/text.html"
cp "$tmp/www/rabbit.mp4" "$tmp/www/rabbit2.mp4"
printf '<!doctype html><title>Rabbit playlist</title><video src="rabbit.mp4"></video><video src="rabbit2.mp4"></video>\n' \
  >"$tmp/www/playlist.html"
printf '<!doctype html><title>Slow page</title><video src="rabbit2.mp4"></video>\n' >"$tmp/www/slow.html"
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
trap 'kill $server; pkill -f "$tmp"; pkill -f "$here/dl --work"; rm -rf "$tmp"' EXIT

# Alpine's BusyBox has nohup, pgrep and pkill; Ubuntu's doesn't, so those come from the system.
# aria2c and yt-dlp are slowed down so a download is still running when the checks look at it.
mkdir "$tmp/bin"
for tool in busybox sh awk base64 cat cut date dd du find grep head ls mkdir mv od rm rmdir sed seq setsid sha256sum sleep sort tail timeout tr wc; do
  ln -s "$(command -v busybox)" "$tmp/bin/$tool"
done
for tool in nohup pgrep pkill kill curl; do ln -s "$(command -v $tool)" "$tmp/bin/$tool"; done
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
SLOW_PAGE=http://127.0.0.1:$port/slow.html                                                      #10

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
update_and_wait() {
  dl -u >/dev/null
  sleep 1
  for try in $(seq 30); do [ -d "$DL_DIR/.logs/.updating" ] || break; sleep 1; done
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

# The Shortcut's screens (dl -ui): what it shows after each tap.
ui() { dl -ui -b "$(b64 "$1")"; }
tap() { ui "$(printf '%s\n' "$screen" | grep -F -- "$1" | head -n 1)"; }  # tap the line containing $1
screen=$(ui @@start)
check "ui: the main menu comes first" "$(printf '%s\n' "$screen" | head -n 1)" "📥 Downloads · "
check "ui: main menu offers the Downloads folder" "$screen" "📂 Open the Downloads folder"
check "ui: Open the Downloads folder gives a Files link" "$(tap '📂')" "shareddocuments://$DL_SHARE"
check "ui: Close" "$(tap '❌')" "@@exit"
check "ui: Add link from clipboard" "$(tap '➕')" "@@clipboard"
check "ui: Open iSH-AOK" "$(tap '📲')" "@@app"
mkdir "$DL_DIR/.logs/.updating"
printf '=== update now\n=== step 1 Alpine packages\n=== step 2 yt-dlp\n' >>"$DL_DIR/.logs/.update.log"
check "ui: an update shows its progress" "$(ui '')" "🔧 Updating · 2 of 3: yt-dlp ▰▰▰▱▱▱▱▱▱▱"
rmdir "$DL_DIR/.logs/.updating"

dl "$SLOW_PAGE" >/dev/null
screen=$(ui @@start)
screen=$(tap '📥 Downloads')
check "ui: the list starts with Back" "$(printf '%s\n' "$screen" | head -n 1)" "⬅️ Back"
finished=$(printf '%s\n' "$screen" | grep -c -E '^(✅|⚠️) ')
[ "$finished" -le 6 ] && echo "ok    ui: the list keeps at most 6 finished downloads" ||
  { echo "FAIL  ui: $finished finished downloads listed"; fails=$((fails + 1)); }
check "ui: tapping a finished download opens it in Files" "$(tap '✅ Rabbit test page')" \
  "shareddocuments://$DL_SHARE/Rabbit%20test%20page%20%281%29.mp4"
for try in $(seq 40); do line_for '#10' | grep -q '% · ' && break; sleep 1; done
screen=$(ui '')
screen=$(tap 'Slow page')
check "ui: tapping a running download shows its screen" "$screen" "⏸ Pause
⏹ Stop and delete"
ls "$DL_DIR" | grep -q '^Slow page.*\.part$' && echo "ok    the slow video is part-way" ||
  { echo "FAIL  no partial file for the slow video"; ls "$DL_DIR"; fails=$((fails + 1)); }
screen=$(tap '⏹ Stop and delete')
check "ui: stopping says so, back on the list" "$screen" "ℹ️ Stopped Slow page"
printf '%s\n' "$screen" | grep 'Slow page' | grep -q ' #[0-9]' &&
  { echo "FAIL  ui: the stopped download is still listed"; fails=$((fails + 1)); } ||
  echo "ok    ui: the stopped download leaves the list"
ls "$DL_DIR" | grep -q '^Slow page' && { echo "FAIL  stop left files behind"; ls "$DL_DIR"; fails=$((fails + 1)); } ||
  echo "ok    stop deletes the partial files"
screen=$(tap 'Nobody Shares This')
screen=$(tap '⏹ Stop and delete')
check "ui: stopping a magnet" "$screen" "ℹ️ Stopped Nobody Shares This"
check "ui: Back goes to the main menu" "$(tap '⬅️ Back')" "📥 Downloads"

# Notifications, through the stand-in for Bark's server.
[ ! -e "$tmp/bark.log" ] && echo "ok    no notifications before they're turned on" ||
  { echo "FAIL  notifications were sent while they were off"; fails=$((fails + 1)); }
screen=$(ui @@start)
check "ui: the main menu offers notifications" "$screen" "🔔 Turn on notifications"
screen=$(tap '🔔')
check "ui: the notifications screen says how to turn them on" "$screen" "2️⃣ In Bark, tap the copy button"
check "ui: 3️⃣ reads the clipboard" "$(tap '3️⃣')" "@@clipboard"
before=$(ls "$DL_DIR/.logs" | grep -c '\.log$')
out=$(dl -b "$(b64 "$SMALL?copied-by-mistake")")
check "after 3️⃣, the clipboard has to have a Bark link" "$out" "There's no Bark link on the clipboard."
[ "$(ls "$DL_DIR/.logs" | grep -c '\.log$')" = "$before" ] && echo "ok    ...and anything else on it isn't downloaded" ||
  { echo "FAIL  after 3️⃣, the clipboard's link was downloaded"; fails=$((fails + 1)); }
out=$(dl -b "$(b64 "$DL_BARK/WRONGKEY/Push content")")
check "a Bark link that Bark doesn't take" "$out" "Bark didn't take that link, so notifications are still off."
out=$(dl -b "$(b64 "Copied from Bark: $DL_BARK/GOODKEY42/Push%20content")")
check "a Bark link turns notifications on" "$out" "Notifications are on. Bark just sent you a test one."
check "...and sends a test notification" "$(cat "$tmp/bark.log")" '"title": "🔔 aria2 notifications are on"'
screen=$(ui '')
check "ui: the notifications screen once they're on" "$screen" "🔔 Send a test notification
🔕 Turn off notifications"
check "ui: sending a test notification" "$(tap '🔔 Send')" "ℹ️ Sent."
check "...which opens the Downloads folder when tapped" "$(tail -n 1 "$tmp/bark.log")" "\"url\": \"shareddocuments://$DL_SHARE\""
screen=$(tap '⬅️ Back')
check "ui: the main menu says they're on" "$screen" "🔔 Notifications · on"

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
grep -q '^NOT JSON' "$tmp/bark.log" && { echo "FAIL  a notification wasn't valid JSON"; fails=$((fails + 1)); } ||
  echo "ok    every notification is valid JSON"

screen=$(tap '🔔')
screen=$(tap '🔕')
check "ui: turning notifications off" "$screen" "ℹ️ Notifications are off."
[ ! -e "$DL_DIR/.logs/.bark" ] && echo "ok    ...and they are" || { echo "FAIL  .bark still there"; fails=$((fails + 1)); }
screen=$(tap '🔔 Turn notifications back on')
check "ui: turning them back on" "$screen" "🔕 Turn off notifications"
screen=$(tap '🔕')
check "ui: Back from notifications" "$(tap '⬅️ Back')" "🔔 Turn on notifications"

dl -p >/dev/null
out=$(act "🧹 Clear finished")
check "clear finished" "$out" "finished download(s). The files are still in Downloads."
out=$(dl -s)
case $out in *NEWS* | *NOPE_404* | *Rabbit*) echo "FAIL  cleared downloads still listed"; fails=$((fails + 1)) ;;
  *) echo "ok    cleared downloads leave the list" ;; esac
[ -e "$DL_SHARE/NEWS" ] && echo "ok    clearing keeps the files" || { echo "FAIL  NEWS was deleted"; fails=$((fails + 1)); }

[ "$fails" = 0 ] && echo "All checks passed." || { echo "$fails check(s) failed."; exit 1; }
