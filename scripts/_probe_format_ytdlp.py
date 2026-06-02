#!/usr/bin/env python3
"""把 yt-dlp -J 的输出转成统一 probe JSON 格式。

Usage: cat ytdlp.json | _probe_format_ytdlp.py <platform> <url>
"""
import json
import sys


def human_size(n):
    if not n:
        return None
    n = float(n)
    for u in ["B", "KiB", "MiB", "GiB"]:
        if n < 1024:
            return f"{n:.1f} {u}"
        n /= 1024
    return f"{n:.1f} TiB"


def codec_short(vcodec, acodec):
    """把 avc1.640028 → h264，hev1.xx → hevc，等。"""
    def shorten(c):
        if not c or c == "none":
            return None
        c = c.lower()
        if c.startswith("avc"):
            return "h264"
        if c.startswith("hev") or c.startswith("hvc"):
            return "hevc"
        if c.startswith("av0") or c.startswith("av1"):
            return "av1"
        if c.startswith("vp9"):
            return "vp9"
        if c.startswith("mp4a"):
            return "aac"
        return c.split(".")[0]
    return shorten(vcodec), shorten(acodec)


def make_label(fmt):
    """根据宽高/编码生成人类可读 label，如 '1080p HEVC'。"""
    h = fmt.get("height")
    fps = fmt.get("fps")
    v_short, _ = codec_short(fmt.get("vcodec"), fmt.get("acodec"))
    parts = []
    if h:
        if h >= 2160:
            parts.append("4K")
        elif h >= 1440:
            parts.append("1440p")
        elif h >= 1080:
            parts.append("1080p")
        elif h >= 720:
            parts.append("720p")
        elif h >= 480:
            parts.append("480p")
        elif h >= 360:
            parts.append("360p")
        else:
            parts.append(f"{h}p")
    if fps and fps >= 48:
        parts[-1] = parts[-1] + f"{int(fps)}"
    if v_short:
        parts.append(v_short.upper())
    if not parts:
        parts.append(fmt.get("format_note", "?"))
    return " ".join(parts)


def main():
    if len(sys.argv) < 3:
        print('{"error":"need platform and url args"}', file=sys.stderr)
        sys.exit(1)
    platform, url = sys.argv[1], sys.argv[2]

    raw_text = sys.stdin.read().strip()
    if not raw_text:
        print('{"error":"empty yt-dlp output"}')
        return
    try:
        raw = json.loads(raw_text)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"json parse failed: {e}"}))
        return

    # 多视频集合（playlist）只取第一个
    if raw.get("_type") == "playlist" and raw.get("entries"):
        raw = raw["entries"][0]

    formats = []
    seen_labels = {}  # 去重：同 label 同 ext 只留最大一个
    for fmt in raw.get("formats", []):
        # 跳过音频纯流（probe 给用户选只展示视频流；合并由 download 阶段处理）
        if fmt.get("vcodec") in (None, "none"):
            continue
        # 跳过 manifest only
        if not fmt.get("url") and not fmt.get("format_id"):
            continue

        v_short, a_short = codec_short(fmt.get("vcodec"), fmt.get("acodec"))
        # 如果是 video-only，搜对应最高码率 audio 算上 filesize
        filesize = fmt.get("filesize") or fmt.get("filesize_approx")
        if fmt.get("acodec") in (None, "none"):
            # 找最大的 audio-only
            audio_fmts = [
                af for af in raw.get("formats", [])
                if af.get("vcodec") in (None, "none")
                and af.get("acodec") not in (None, "none")
            ]
            audio_fmts.sort(key=lambda x: x.get("abr") or 0, reverse=True)
            if audio_fmts:
                a_sz = (
                    audio_fmts[0].get("filesize")
                    or audio_fmts[0].get("filesize_approx")
                )
                if filesize and a_sz:
                    filesize = filesize + a_sz
                a_short = codec_short(None, audio_fmts[0].get("acodec"))[1]

        label = make_label(fmt)
        # 构造 -f 表达式：video-only 的需要 +bestaudio 合并
        fid = fmt.get("format_id")
        if fmt.get("acodec") in (None, "none"):
            format_arg = f"{fid}+bestaudio/best"
        else:
            format_arg = str(fid)

        entry = {
            "id": str(fid),
            "label": label,
            "width": fmt.get("width"),
            "height": fmt.get("height"),
            "fps": fmt.get("fps"),
            "vcodec": v_short,
            "acodec": a_short,
            "ext": fmt.get("ext"),
            "filesize": filesize,
            "filesize_human": human_size(filesize) if filesize else None,
            "tbr": fmt.get("tbr"),
            "note": fmt.get("format_note", "") or "",
            "format_arg": format_arg,
        }
        # 同 label+ext 去重：保留 filesize 更大的（更高码率）
        key = (label, entry["ext"])
        existing = seen_labels.get(key)
        if existing and (existing.get("filesize") or 0) >= (filesize or 0):
            continue
        seen_labels[key] = entry

    # 按 height desc, filesize desc 排序
    final = sorted(
        seen_labels.values(),
        key=lambda x: (-(x.get("height") or 0), -(x.get("filesize") or 0)),
    )

    out = {
        "platform": platform,
        "url": url,
        "title": raw.get("title", ""),
        "uploader": raw.get("uploader") or raw.get("channel") or "",
        "upload_date": raw.get("upload_date", ""),
        "duration": raw.get("duration"),
        "thumbnail": raw.get("thumbnail", ""),
        "formats": final,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
