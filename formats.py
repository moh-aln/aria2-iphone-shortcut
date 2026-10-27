#!/usr/bin/env python3
"""The qualities a video comes in, for "Choose the quality" in dl's menu.

    python3 formats.py <what yt-dlp -J printed>

prints one row per line, its fields joined by \\x1f, for dl to show:
    title     <the video's or playlist's title>
    thumbnail <its picture's link>
    playlist  <how many videos>                  (a playlist: no qualities to pick from)
    video     <format> <label> <detail> <1 if it has its own sound, else 0>
    audio     <format> <label> <detail>
Videos come one per resolution, best first: one the iPhone plays everywhere (H.264) where
the site has it, then one with its own sound, which needs no second download, then the
highest bitrate. Each says whether its sound comes with it, is picked next, or doesn't
exist. Sounds come best first.
"""
import json
import sys

SEP = "\x1f"


def codec(name):
    name = (name or "").lower()
    for prefix, label in (("avc", "H.264"), ("h264", "H.264"), ("vp09", "VP9"), ("vp9", "VP9"), ("av01", "AV1"),
                          ("hev", "HEVC"), ("hvc", "HEVC"), ("mp4a", "AAC"), ("aac", "AAC"), ("opus", "Opus"),
                          ("vorbis", "Vorbis"), ("mp3", "MP3"), ("ec-3", "Dolby"), ("ac-3", "Dolby"), ("flac", "FLAC")):
        if name.startswith(prefix):
            return label
    return name.split(".")[0].upper() if name not in ("", "none") else ""


def size(f):
    n = f.get("filesize") or f.get("filesize_approx")
    if not n:
        return ""
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") or n >= 100 else f"{n:.1f} {unit}"
        n /= 1024
    return ""


def has(value):
    # Sites that don't say what codec a format has: assume it has one. Formats without
    # sound or picture always say "none".
    return value != "none"


def plays(f):
    # H.264 plays everywhere on the iPhone. So, likely, does an MP4 whose codec the site
    # doesn't say: X's progressive MP4s, which have their sound in them.
    name = codec(f.get("vcodec"))
    return name == "H.264" or (name == "" and f.get("ext") in ("mp4", "m4v", "mov"))


def row(*fields):
    print(SEP.join(str(x).replace(SEP, " ").replace("\n", " ") for x in fields))


def main(path):
    with open(path, encoding="utf-8") as f:
        info = json.load(f)
    row("title", info.get("title") or info.get("id") or "")
    if info.get("thumbnail"):
        row("thumbnail", info["thumbnail"])
    if info.get("_type") == "playlist":
        row("playlist", info.get("playlist_count") or len(info.get("entries") or []))
        return
    formats = [f for f in info.get("formats") or [info] if f.get("url") or f.get("format_id")]
    formats = [f for f in formats if "storyboard" not in (f.get("format_note") or "") and f.get("ext") != "mhtml"]

    # Sounds on their own: one of each codec, bitrate and language, best first.
    seen, sounds = set(), []
    languages = {f.get("language") for f in formats if f.get("vcodec") == "none" and has(f.get("acodec"))}
    for f in formats:
        if f.get("vcodec") != "none" or not has(f.get("acodec")) or "drc" in str(f.get("format_id")):
            continue
        name, rate = codec(f.get("acodec")), round(f.get("abr") or f.get("tbr") or 0)
        key = (name, rate, f.get("language"))
        if key in seen:
            continue
        seen.add(key)
        sounds.append((rate, name == "AAC", f, name))
    sounds = sorted(sounds, key=lambda s: (s[1], s[0]), reverse=True)[:8]

    # Videos: the best of each height (and frame rate).
    best = {}
    for f in formats:
        if f.get("vcodec") == "none":
            continue
        fps = f.get("fps") or 0
        key = (f.get("height") or 0, 60 if fps > 30 else 30)
        rank = (plays(f), has(f.get("acodec")), f.get("tbr") or 0)
        if key not in best or rank > best[key][0]:
            best[key] = (rank, f)
    for (height, fps), (_, f) in sorted(best.items(), key=lambda kv: kv[0], reverse=True):
        name = codec(f.get("vcodec"))
        label = f"{height}p" + ("60" if fps == 60 else "") if height else (f.get("format_note") or f.get("ext") or "Video")
        own = has(f.get("acodec"))
        sound = "with sound" if own else ("sound next" if sounds else "no sound")
        detail = " · ".join(x for x in (name, size(f), "plays everywhere" if plays(f) else "may not play in Files", sound) if x)
        row("video", f["format_id"], label, detail, 1 if own else 0)

    for rate, _, f, name in sounds:
        label = " · ".join(x for x in (name, f"{rate} kbps" if rate else "") if x)
        if len(languages) > 1 and f.get("language"):
            label += f" · {f['language']}"
        plays_ = "plays everywhere" if name in ("AAC", "MP3") else "may not play everywhere"
        row("audio", f["format_id"], label, " · ".join(x for x in (size(f), plays_) if x))


if __name__ == "__main__":
    main(sys.argv[1])
