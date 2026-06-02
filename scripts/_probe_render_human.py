#!/usr/bin/env python3
"""把 probe JSON 渲染成人类可读表格。"""
import json
import sys


def human_size(n):
    if not n:
        return "?"
    n = float(n)
    for u in ["B", "KiB", "MiB", "GiB"]:
        if n < 1024:
            return f"{n:.1f} {u}"
        n /= 1024
    return f"{n:.1f} TiB"


def main():
    data = json.load(sys.stdin)
    if "error" in data:
        print(f"❌ probe error: {data['error']}")
        sys.exit(1)

    print("=" * 78)
    print(f"平台    : {data.get('platform', '?')}")
    print(f"标题    : {data.get('title', '?')}")
    print(f"作者    : {data.get('uploader', '?')}")
    print(f"发布日期: {data.get('upload_date', '?')}")
    dur = data.get("duration")
    if dur:
        print(f"时长    : {int(dur) // 60}m{int(dur) % 60:02d}s")
    url = data.get("url", "?")
    print(f"URL     : {url[:80]}{'...' if len(url) > 80 else ''}")
    print("-" * 78)
    print(f"{'#':>3} {'画质':<14} {'编码':<12} {'容器':<6} {'大小':>10}  备注")
    print("-" * 78)
    formats = data.get("formats", [])
    if not formats:
        print("    (no video formats found)")
    for i, f in enumerate(formats):
        label = (f.get("label") or "?")[:13]
        v = f.get("vcodec") or "?"
        a = f.get("acodec") or "-"
        codec = f"{v}+{a}"[:11]
        ext = (f.get("ext") or "?")[:5]
        size = f.get("filesize_human") or human_size(f.get("filesize") or 0)
        note = (f.get("note") or "")[:30]
        print(f"{i:>3} {label:<14} {codec:<12} {ext:<6} {size:>10}  {note}")
    print("=" * 78)
    print()
    print("用法：")
    print("  bash scripts/download.sh --format <#> <URL>     # 按行号下载")
    print("  bash scripts/download.sh --format-id <id> <URL> # 按 format-id 下载")
    print("  bash scripts/download.sh quality <URL>          # 自动选最高画质")
    print()


if __name__ == "__main__":
    main()
