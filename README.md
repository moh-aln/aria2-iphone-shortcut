# aria2 iPhone Shortcut

Share any link on your iPhone and it downloads, entirely on the phone, without a computer.

- Video pages (YouTube, Instagram, X, TikTok and many more sites) go to [yt-dlp](https://github.com/yt-dlp/yt-dlp).
- Files, `.torrent` links and magnet links go to [aria2](https://github.com/aria2/aria2).

Both run in Alpine Linux inside the [iSH-AOK](https://github.com/emkey1/ish-AOK) app. One Apple Shortcut drives them. Its menus have a picture on every row: progress rings for downloads, and each video's own thumbnail once it's done.

- **Type:** tool (iOS Shortcut + shell script)
- **Started:** 2026-10-26
- **Status:** working on an iPhone with iOS 26: files, YouTube videos, background downloading

## What's here

| file | what it is |
| --- | --- |
| `dl` | the script that runs inside iSH-AOK. It picks yt-dlp or aria2 for each link, downloads in the background, lists downloads with progress bars, pauses and resumes them, and updates itself and its tools |
| `shortcuts/setup-on-phone.sh` | sets everything up on the phone, and is what updates install: the tools, `dl`, location access, and the signed shortcut |
| `build_shortcuts.py` | writes `shortcuts/aria2.shortcut` (unsigned), `shortcuts/setup-on-phone.sh` and `icons/` |
| `web.py` | the live view and the player: a small web server, started by `dl` when they're opened |
| `icons.py`, `icons/` | draws the menus' pictures (Python's standard library only); `icons/` has them as PNGs to look at |
| `test.sh` | checks `dl` on a computer, using BusyBox tools like the phone does (needs `aria2c`, `yt-dlp`, `busybox`, `curl`, `ffmpeg` and `python3`) |

**Which tool gets a link:**
- Magnet, ftp and sftp links go to aria2.
- Links to known video sites (YouTube, Instagram, X, TikTok, Facebook, Reddit, Vimeo and others, listed in `dl`) go to yt-dlp.
- For any other web link, `dl` checks what the server sends back. A web page goes to yt-dlp, which finds videos in pages; anything else is a file for aria2.

## Install on the iPhone

1. Install **iSH-AOK** from TestFlight: https://testflight.apple.com/join/X1flyiqE
2. On first launch, pick **Alpine 3.24.2**, then **arm64**.
3. Give iSH-AOK a Files folder for finished downloads. In iSH-AOK, run:
   ```
   mkdir -p /mnt/phone && mount -t ios phone /mnt/phone
   ```
   Pick a folder such as **On My iPhone → Downloads**. Each finished download is moved there, and iSH-AOK remembers the folder across launches.
4. Run the setup:
   ```
   apk add curl && curl -fsSLo /root/setup-on-phone.sh https://raw.githubusercontent.com/moh-aln/aria2-iphone-shortcut/main/shortcuts/setup-on-phone.sh && sh /root/setup-on-phone.sh
   ```
   This installs aria2, yt-dlp, Node, QuickJS, ffmpeg and `dl`, about 150 MB the first time. It also asks for location access. Finally, it sends the shortcut to RoutineHub's HubSign service to be signed, because iOS only imports signed shortcuts. The shortcut holds nothing private: it contains commands like `dl -ui` and iSH-AOK's app ID.
5. Import the shortcut: in Files, open the folder from step 3, tap **aria2.shortcut** and add it. It's always that name there; each new version replaces the one before.
6. Settings → Apps → **iSH-AOK** → **Location**: choose **Always**, and turn **Precise Location** off. iOS keeps iSH-AOK running in the background only while it gets location updates. `dl` asks for them while something is downloading and stops when nothing is. Without Always, downloads only move while iSH-AOK is open.

## Using the "aria2" shortcut

- **Share a link** to it (from Safari, YouTube, Instagram, X or any app's Share button). It starts downloading in the background and shows a notification.
- **Run it on its own** (Home Screen, Shortcuts app or Siri) for its menu. Each row has a picture and a line under its title:

```
📥 Downloads              1 downloading · 3 finished
➕ Add link from clipboard  Copy a link, then tap here
📂 Downloads folder       Open it in Files
⚙️ Settings               Notifications on · automatic updates
```

**📥 Downloads** shows the list, newest first:

```
⬅️ Back
📊 Watch live             Progress bars that move as they download
⏳ youtube.com video      Preparing 50% · unlocking the video link, about a minute…
⬇️ big-file.zip           32% · 1.2MiB/s · 30s left
⬇️ My Playlist            Video 3 of 12 · 45% · 1.2MiB/s
⏸ other-file.tar.xz      Paused at 32%
✅ Rabbit                 Downloaded · 816K
⏸ Pause all  ·  ▶️ Resume all  ·  🧹 Clear finished  ·  🔄 Refresh
```

- **The pictures:** a ring that fills up as a download goes (orange while it's preparing, blue while it downloads), a pause sign, a tick, or for a finished video, its own thumbnail.
- **Tap a download** for its own menu. A finished one has:
  - **▶️ Open:** plays a video or music right there, in a sheet, and shows pictures, PDFs and text. A playlist lists its videos to play.
  - **📂 Show in folder:** its folder in the Files app.
  - **🔁 Download again:** from the start, for when the file was moved or deleted. If it's still there, you keep one copy; if the new file is different, it's saved next to the old one as `name (2)`.
  - **🔗 Copy link** and **📤 Share link:** the link it was downloaded from.
  - **➖ Remove from the list** (the file stays), and **🗑 Delete the file…**, which asks first.
- **A download that's still going** has **⏸ Pause** or **▶️ Resume**, **📊 Watch live**, and **⏹ Stop and delete**, which stops it, deletes what it downloaded so far and removes it from the list. Failed downloads offer **🔁 Try again**.
- **A playlist part-way** offers **⏹ Stop here** instead: it keeps the videos it already finished (they go to Files like any download), deletes only the one it was on, and stays in the list as `Stopped · 3 of 12 videos`.
- **⏳ Preparing** is everything before the download itself. For YouTube that's mostly unlocking the video link, which takes about a minute.
- The list keeps only the 6 most recent finished downloads, and **🧹 Clear finished** removes them all. The files always stay. The buttons at the bottom only show when there's something for them to do.
- **Playlists:** a playlist link (not a video that happens to be in one) downloads the whole playlist into a folder named after it. The ring is for the whole playlist.
- **Videos** are saved as MP4 (H.264 when the site offers it, which plays everywhere on the iPhone), named after their title.
- **To close the menu**, swipe it down.

**📊 Watch live** opens a page with every download on it, refreshed every second: bars and rings that move as the downloads do, the speed and time left, and buttons to pause, resume, stop, open or download again. You can paste a link into it too. Tap **Done** to go back to the menu.

It's a small web server in iSH-AOK (`web.py`), on 127.0.0.1 only and with a new password-like token each time it starts, so nothing else on the phone can use it. It stops by itself 5 minutes after the page was last open. **▶️ Open** uses it too.

**⚙️ Settings** has everything else:

```
⬅️ Back
🔔 Notifications          On: one when a download finishes
⬆️ aria2 and its shortcut  Up to date · checked 2 h ago
🔧 Tools: yt-dlp, aria2, ffmpeg  Updated 5 h ago · yt-dlp 2026.10.21
🔁 Automatic updates      On: tools daily, aria2 when you open it
🖼 Pictures in menus      On
📲 Open iSH-AOK           The terminal behind aria2
```

All of these screens come from `dl` itself; the shortcut only shows them. So new menus arrive with `dl`'s updates, without importing a new shortcut. With **🖼 Pictures in menus** off, they're plain lines of text.

## Notifications

`dl` can send a notification when a download finishes, saying what was downloaded. Tapping it opens the file (or a playlist's folder) in the Files app. A failed download gets one too. They're off until you turn them on in **⚙️ Settings → 🔔 Notifications**.

iSH-AOK can't post notifications itself, so they go through [Bark](https://github.com/Finb/Bark), a free, open-source notification app:

1. Tap **1️⃣ Get Bark**, which opens the App Store. Install Bark, open it and allow its notifications.
2. In Bark, tap the copy button next to any of its example links (they look like `https://api.day.app/<your key>/…`).
3. Back in aria2's notifications screen, tap **3️⃣ Then tap here**. (Sharing that Bark link to aria2 works too.)

Bark sends a test notification straight away. Once they're on, the same screen has **🔔 Send a test notification** and **🔕 Turn off notifications**.

Each notification's text (the file name, its size and its place in Files) goes to Bark's server at api.day.app, which hands it to Apple to deliver. Your key stays in iSH-AOK, in `/root/Downloads/.logs/.bark`.

## Updates

There are two kinds, each with its own row in **⚙️ Settings**, and each automatic unless **🔁 Automatic updates** is off:

- **🔧 Tools:** `yt-dlp -U` (YouTube changes often), plus aria2, ffmpeg, Node, QuickJS and curl from Alpine. Once a day, after a download or when you open the shortcut.
- **⬆️ aria2 and its shortcut:** this repository's `shortcuts/setup-on-phone.sh`, run whenever it differs from the one that last ran. It installs the new `dl` and, if the shortcut changed, signs the new one and puts it in your Files folder as **aria2.shortcut**, replacing the one before. It's checked when you open the shortcut (at most every 6 hours) and once a day after a download.

When a new shortcut is ready, the next time you open aria2 it opens the new shortcut for you, and iOS asks whether to add it: choose **Replace**. Until you do, the main menu has a **🆕 New aria2 shortcut** row that does the same. Once the new shortcut runs, the row goes away by itself.

Updates run code from this repository as root inside iSH-AOK, so only push here what you'd run on your phone.

## `dl` from the iSH-AOK terminal

```
dl <link>      download (or resume) a link
dl <Bark link> turn on notifications
dl -s          the list with progress bars
dl -p | -r     pause all | resume all
dl -c          clear finished from the list
dl -u | -v     update aria2 and its tools now | show the tools' versions
```

## Signing on a Mac instead

`shortcuts/aria2.shortcut` is unsigned. On a Mac, sign it and AirDrop it to the iPhone:

```
shortcuts sign -m anyone -i aria2.shortcut -o "aria2 (signed).shortcut"
```

## How to run the tests

From this folder: `sh test.sh`

## Limits

- **YouTube is slow to start.** Every YouTube video's download address is scrambled, and only YouTube's own player JavaScript (several MB, deliberately obfuscated) can unscramble it. yt-dlp runs that for every video inside iSH-AOK's Linux emulation, which shows as "Solving JS challenges". With Node it takes about 40 seconds on an iPhone; with QuickJS, about 2½ minutes. Each video in a playlist pays it again.
- **Background:** iOS may still pause location updates when the phone sits still for a long time, and then the download waits until iSH-AOK is opened. A single Run Command can last 120 seconds at most, which is why `dl` starts every download in the background and returns at once.
- **Instagram** often refuses downloads without a login, and Instagram stories always need one. yt-dlp can use cookies from a logged-in browser, but `dl` doesn't pass any yet.
- **Torrents** stop as soon as they finish (no seeding). If a torrent gets no data for 15 minutes, it gives up; tap it in the list to try again.
- **`.torrent` files** shared as files (rather than as links) aren't handled yet. Magnet links and links to `.torrent` files work.
- **Files' iSH-AOK location** can get stuck on "Loading". That's why finished downloads go to a folder you mount yourself (install step 3). Writing into a file in that folder while Files has it open can hang, so a new shortcut is copied in under another name first and then swapped in.
- **The live view and the player** need iSH-AOK to stay running in the background, so they need location access set to **Always** (install step 6), like background downloads do.
- **If the menus with pictures ever misbehave**, turn the pictures off from the iSH-AOK terminal: `touch /root/Downloads/.logs/.plain` (delete that file to turn them back on).
- **Security:** any shortcut on the phone can run commands as root inside iSH-AOK. Don't import shortcuts you haven't read.
