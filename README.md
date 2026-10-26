# aria2 iPhone Shortcut

Share any link on your iPhone and it downloads, entirely on the phone, without a computer.

- Video pages (YouTube, Instagram, X, TikTok and many more sites) go to [yt-dlp](https://github.com/yt-dlp/yt-dlp).
- Files, `.torrent` links and magnet links go to [aria2](https://github.com/aria2/aria2).

Both run in Alpine Linux inside the [iSH-AOK](https://github.com/emkey1/ish-AOK) app. One Apple Shortcut drives them, with a download list that has progress bars and pause and resume.

- **Type:** tool (iOS Shortcut + shell script)
- **Started:** 2026-10-26
- **Status:** working on an iPhone with iOS 26: files, YouTube videos, background downloading

## What's here

| file | what it is |
| --- | --- |
| `dl` | the script that runs inside iSH-AOK. It picks yt-dlp or aria2 for each link, downloads in the background, lists downloads with progress bars, pauses and resumes them, and updates itself and its tools |
| `shortcuts/setup-on-phone.sh` | sets everything up on the phone, and is what updates install: the tools, `dl`, location access, and the signed shortcut |
| `build_shortcuts.py` | writes `shortcuts/aria2.shortcut` (unsigned) and `shortcuts/setup-on-phone.sh` |
| `test.sh` | checks `dl` on a computer, using BusyBox tools like the phone does (needs `aria2c`, `yt-dlp`, `busybox`, `curl` and `python3`) |

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
   This installs aria2, yt-dlp, Node, QuickJS, ffmpeg and `dl`, about 150 MB the first time. It also asks for location access. Finally, it sends the shortcut to RoutineHub's HubSign service to be signed, because iOS only imports signed shortcuts. The shortcut holds nothing private: it contains commands like `dl -m` and iSH-AOK's app ID.
5. Import the shortcut: in Files, open the folder from step 3, tap **aria2-….shortcut** and add it. The setup's last lines name the file.
6. Settings → Apps → **iSH-AOK** → **Location**: choose **Always**, and turn **Precise Location** off. iOS keeps iSH-AOK running in the background only while it gets location updates. `dl` asks for them while something is downloading and stops when nothing is. Without Always, downloads only move while iSH-AOK is open.

## Using the "aria2" shortcut

- **Share a link** to it (from Safari, YouTube, Instagram, X or any app's Share button). It starts downloading in the background and shows a notification.
- **Run it on its own** (Home Screen, Shortcuts app or Siri) for its menu:

```
📥 Downloads · 1 downloading, 3 finished
➕ Add link from clipboard
📂 Open the Downloads folder
🔧 Update tools
📲 Open iSH-AOK
❌ Close
```

**📥 Downloads** shows the list:

```
⬅️ Back
⏳ ▰▰▰▰▰▱▱▱▱▱ 50% preparing · unlocking the video link, about a minute… · youtube.com video  #5
⬇️ ▰▰▰▱▱▱▱▱▱▱ 32% · big-file.zip · 1.2MiB/s · 30s left  #4
⬇️ ▰▰▱▱▱▱▱▱▱▱ video 3 of 12 · 45% · 1.2MiB/s · 📃 My Playlist  #3
⏸ ▰▰▰▱▱▱▱▱▱▱ 32% · other-file.tar.xz · paused  #2
✅ rabbit320.mp4 · 816K  #1
⏸ Pause all
▶️ Resume all
🧹 Clear finished
🔄 Refresh
```

- **Tap a finished download** to open it in the Files app, which plays videos and music. A playlist opens its folder.
- **Tap any other download** for its own screen: **⏸ Pause** or **▶️ Resume**, and **⏹ Stop and delete**, which stops it, deletes what it downloaded so far and removes it from the list. Failed downloads offer **🔁 Try again**.
- **⏳ preparing** is everything before the download itself. For YouTube that's mostly unlocking the video link, which takes about a minute.
- The list keeps only the 6 most recent finished downloads, and **🧹 Clear finished** removes them all. The files always stay.
- **Playlists:** a playlist link (not a video that happens to be in one) downloads the whole playlist into a folder named after it. The bar is for the whole playlist. When it finishes, the line reads `✅ 📃 My Playlist · 12 videos`, plus how many failed, if any.
- **Videos** are saved as MP4 (H.264 when the site offers it, which plays everywhere on the iPhone), named after their title.
- **Close the menu with ❌** (or swipe it away) when you're done: while it's open, the shortcut keeps running.

All of these screens come from `dl` itself; the shortcut only shows them. So new menus arrive with `dl`'s updates, without importing a new shortcut.

## Updates

Once a day, after a download, `dl` updates itself and its tools in the background. **🔧 Update tools** in the menu does it right away, and shows which of its 3 steps it's on. An update:
- runs `yt-dlp -U`, since YouTube changes often
- updates aria2, ffmpeg, Node, QuickJS and curl from Alpine
- runs this repository's `shortcuts/setup-on-phone.sh` whenever it differs from the one that last ran. That's how a new `dl` arrives.

If the shortcut itself changed, the list shows a **🆕 New shortcut** line saying where the new one is; iOS needs you to open it and tap **Replace**. Updates run code from this repository as root inside iSH-AOK, so only push here what you'd run on your phone.

## `dl` from the iSH-AOK terminal

```
dl <link>      download (or resume) a link
dl -s          the list with progress bars
dl -p | -r     pause all | resume all
dl -c          clear finished from the list
dl -u | -v     update now | show tool versions
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
- **Files' iSH-AOK location** can get stuck on "Loading". That's why finished downloads go to a folder you mount yourself (install step 3). Writing over a file in that folder while Files has it open can hang, which is why new shortcuts get a new name there.
- **Security:** any shortcut on the phone can run commands as root inside iSH-AOK. Don't import shortcuts you haven't read.
