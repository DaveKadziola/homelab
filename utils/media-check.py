#!/usr/bin/env python3
"""Find films that Jellyfin cannot hand to clients as they are; with --apply, remux the ones it can fix.

  utils/media-check.py /mnt/nas/media/video/movies            # report only
  utils/media-check.py /mnt/nas/media/video/movies --apply    # remux, then move the originals away
  utils/media-check.py --self-test

Runs on the laptop against the Samba share (ffprobe and ffmpeg there), so the J4205 never
encodes: Jellyfin has video transcoding off (utils/bootstrap/jellyfin.sh). Per file:
  ok        MKV/MP4 with H.264 or HEVC video
  remux     H.264/HEVC in another container (AVI, MPEG-TS, ...): copied into MKV, no quality loss
  reencode  other video codecs: reported only, a client without that decoder cannot play them
  unreadable  ffprobe failed on the file
Notes flag what still needs a capable client: image or ASS subtitles (burn-in), 10-bit HEVC.
--apply writes <name>.mkv next to the original, checks that every stream kept all its packets
and, for AVI, that frames are evenly timed, and only then moves the original to <root>/../_originals/<root
name>/..., outside the Jellyfin libraries. An existing <name>.mkv is never overwritten.
Exit code: 0 done, 1 a remux failed its checks or the self-test failed, 2 ffprobe or ffmpeg missing.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

VIDEO_EXT = {".avi", ".mkv", ".mp4", ".m4v", ".mov", ".wmv", ".mpg", ".mpeg", ".ts", ".m2ts", ".flv", ".webm"}
GOOD_CONTAINERS = {".mkv", ".mp4", ".m4v"}
COPYABLE_VIDEO = {"h264", "hevc"}
BURN_IN_SUBS = {"hdmv_pgs_subtitle", "dvd_subtitle", "ass", "ssa"}


def classify(ext, streams):
    """(action, notes) for a file extension and its ffprobe streams."""
    video = next((s for s in streams if s.get("codec_type") == "video"
                  and not s.get("disposition", {}).get("attached_pic")), None)
    notes = []
    subs = sorted({s["codec_name"] for s in streams if s.get("codec_type") == "subtitle"} & BURN_IN_SUBS)
    if subs:
        notes.append("subtitles " + ",".join(subs) + " need burn-in in a browser")
    if video is None:
        return "reencode", ["no video stream"] + notes
    if video["codec_name"] == "hevc" and "10" in video.get("pix_fmt", ""):
        notes.append("10-bit HEVC: browsers mostly cannot play it")
    if video["codec_name"] not in COPYABLE_VIDEO:
        return "reencode", [f"video {video['codec_name']}"] + notes
    if ext not in GOOD_CONTAINERS:
        return "remux", [f"container {ext[1:]}"] + notes
    return "ok", notes


def even_timing(pts, tolerance=0.002):
    """True when the sorted presentation times step by one frame duration (constant frame rate)."""
    pts = sorted(pts)
    steps = [b - a for a, b in zip(pts, pts[1:])]
    if not steps:
        return False
    step = sorted(steps)[len(steps) // 2]
    return all(abs(s - step) <= tolerance for s in steps)


def probe(path, *extra):
    out = subprocess.run(["ffprobe", "-v", "error", "-of", "json", *extra, str(path)],
                         capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def streams_of(path):
    return probe(path, "-show_entries", "stream=index,codec_type,codec_name,pix_fmt:stream_disposition=attached_pic")


def packets(path):
    """Sorted (stream type, packet count); reads the whole file."""
    s = probe(path, "-count_packets", "-show_entries", "stream=codec_type,nb_read_packets")
    return sorted((x["codec_type"], int(x["nb_read_packets"])) for x in s["streams"])


def first_pts(path, seconds=60):
    p = probe(path, "-select_streams", "v:0", "-read_intervals", f"%+{seconds}", "-show_entries", "packet=pts_time")
    return [float(x["pts_time"]) for x in p.get("packets", []) if x.get("pts_time") not in (None, "N/A")]


def remux(src, root):
    dst = src.with_suffix(".mkv")
    if dst.exists():
        return f"skipped, {dst.name} exists"
    tmp = src.with_name(f".{src.stem}.remux.mkv")
    # AVI keeps no presentation times for B-frames; +genpts rebuilds them once, here, not on every play.
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-fflags", "+genpts", "-i", str(src),
                    "-map", "0", "-c", "copy", "-f", "matroska", "-y", str(tmp)], check=True)
    # Packets, not the header duration: an AVI header can claim frames the file does not hold.
    problems = []
    before, after = packets(src), packets(tmp)
    if before != after:
        problems.append(f"packets per stream {before} -> {after}")
    if src.suffix.lower() == ".avi" and not even_timing(first_pts(tmp)):
        problems.append("uneven frame timing in the first 60 s")
    if problems:
        tmp.unlink()
        raise RuntimeError("; ".join(problems))
    tmp.rename(dst)
    keep = root.parent / "_originals" / root.name / src.relative_to(root)
    keep.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(keep))
    return f"remuxed to {dst.name}, original in {keep}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", type=Path)
    ap.add_argument("--apply", action="store_true", help="remux the 'remux' files")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if not args.root:
        ap.error("root is required")
    if not (shutil.which("ffprobe") and shutil.which("ffmpeg")):
        print("ffprobe and ffmpeg are required", file=sys.stderr)
        return 2
    root, failed, totals = args.root.resolve(), 0, {}
    for path in sorted(p for p in root.rglob("*") if p.suffix.lower() in VIDEO_EXT and p.is_file()
                       and not p.name.startswith(".")):
        try:
            action, notes = classify(path.suffix.lower(), streams_of(path)["streams"])
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            action, notes = "unreadable", []
        totals[action] = totals.get(action, 0) + 1
        if action == "ok" and not notes:
            continue
        line = f"{action:9} {path.relative_to(root)}" + (f"  ({'; '.join(notes)})" if notes else "")
        if args.apply and action == "remux":
            try:
                line += f"\n          {remux(path, root)}"
            except (subprocess.CalledProcessError, RuntimeError, OSError) as e:
                failed += 1
                line += f"\n          NOT remuxed, original untouched: {e}"
        print(line)
    print("total: " + ", ".join(f"{k} {v}" for k, v in sorted(totals.items())))
    return 1 if failed else 0


def self_test():
    v = lambda codec, fmt="yuv420p": {"codec_type": "video", "codec_name": codec, "pix_fmt": fmt}
    a = {"codec_type": "audio", "codec_name": "ac3"}
    assert classify(".mkv", [v("h264"), a]) == ("ok", [])
    assert classify(".avi", [v("h264"), a]) == ("remux", ["container avi"])
    assert classify(".avi", [v("mpeg4"), a])[0] == "reencode"
    assert classify(".mp4", [v("hevc", "yuv420p10le"), a]) == ("ok", ["10-bit HEVC: browsers mostly cannot play it"])
    pgs = {"codec_type": "subtitle", "codec_name": "hdmv_pgs_subtitle"}
    assert classify(".mkv", [v("h264"), a, pgs])[1] == ["subtitles hdmv_pgs_subtitle need burn-in in a browser"]
    cover = {"codec_type": "video", "codec_name": "mjpeg", "disposition": {"attached_pic": 1}}
    assert classify(".mkv", [cover, v("h264"), a]) == ("ok", [])
    assert even_timing([0.0, 0.0834, 0.0417, 0.1251])
    assert not even_timing([0.0, 0.0417, 0.1251, 0.1668])
    assert not even_timing([])
    print("media-check self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
