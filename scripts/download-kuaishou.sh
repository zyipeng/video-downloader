#!/usr/bin/env bash
# ===================================================================
# Kuaishou (快手) Video Downloader
# -------------------------------------------------------------------
# yt-dlp 没有内置快手 extractor（2026-06 实测），所以本脚本走 SSR
# 的 share 页面：分享页 HTML 里直接 inline 了 mp4 直链（hd15 / b 普通）。
#
# 已验证 URL 模式：
#   - https://www.kuaishou.com/f/<shareToken>           (短链)
#   - https://www.kuaishou.com/short-video/<photoId>    (长链)
#   - https://v.kuaishou.com/<shortCode>                (App 分享)
#
# 用法: download-kuaishou.sh <MODE> <URL> [output_dir]
#   MODE:  quality | speed | compat
# ===================================================================
set -euo pipefail

# ===== --probe-only mode =====
PROBE_ONLY=0
if [[ "${1:-}" == "--probe-only" ]]; then
  PROBE_ONLY=1
  shift
fi

MODE="${1:-compat}"
URL="${2:-}"
OUT_DIR="${3:-$HOME/Downloads}"

if [[ -z "$URL" ]]; then
  echo "Usage: $0 [--probe-only] <quality|speed|compat> <URL> [output_dir]" >&2
  exit 1
fi

# UA: iPhone Safari，最稳。其它 UA 有时会拿到无 mp4 的页面
UA="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

mkdir -p "$OUT_DIR"
HTML_TMP="$(mktemp -t ks-html.XXXXXX)"
trap 'rm -f "$HTML_TMP"' EXIT

echo ">>> [kuaishou] Fetching share page (SSR)..."
if ! curl -sSL --compressed \
     -A "$UA" \
     -H "Accept-Language: zh-CN,zh;q=0.9" \
     --max-time 20 --retry 2 \
     "$URL" -o "$HTML_TMP"; then
  echo "❌ Failed to fetch Kuaishou share page" >&2
  exit 1
fi

# 从 HTML / URL 里抓 photoId（多源 fallback；用 || true 防 set -e 杀掉）
PHOTO_ID="$(grep -oE 'short-video/[a-zA-Z0-9_-]+' "$HTML_TMP" 2>/dev/null | head -1 | sed 's|short-video/||' || true)"
if [[ -z "$PHOTO_ID" ]]; then
  PHOTO_ID="$(grep -oE 'clientCacheKey=[a-zA-Z0-9_-]+' "$HTML_TMP" 2>/dev/null | head -1 | sed 's|clientCacheKey=||' | sed 's|_.*||' || true)"
fi
if [[ -z "$PHOTO_ID" ]]; then
  PHOTO_ID="$(echo "$URL" | grep -oE '/(short-video|f|photo)/[a-zA-Z0-9_-]+' 2>/dev/null | sed -E 's|.*/||' || true)"
fi
PHOTO_ID="${PHOTO_ID:-kuaishou_video}"
echo ">>> [kuaishou] photoId: $PHOTO_ID"

# 用 python3 提取 mp4 直链（多档质量都有）
PY_SCRIPT="$(mktemp -t ks-extract.XXXXXX.py)"
trap 'rm -f "$HTML_TMP" "$PY_SCRIPT"' EXIT

cat > "$PY_SCRIPT" << 'PY'
import re, sys
path, mode = sys.argv[1], sys.argv[2]
with open(path) as f:
    html = f.read()

urls = re.findall(r'https?://[^\s"\']+?\.mp4(?:\?[^\s"\']+)?', html)
seen = {}
for u in urls:
    base = u.split('?')[0]
    if base not in seen:
        seen[base] = u

if not seen:
    sys.exit(0)

hd_urls   = [u for b,u in seen.items() if 'hd15' in b or '_hd' in b]
std_urls  = [u for b,u in seen.items() if '_b_' in b]
other     = [u for b,u in seen.items() if u not in hd_urls and u not in std_urls]

if mode == "speed":
    candidate = (std_urls + hd_urls + other)
else:
    candidate = (hd_urls + std_urls + other)

if candidate:
    print(candidate[0], end="")
PY

SELECTED_URL="$(python3 "$PY_SCRIPT" "$HTML_TMP" "$MODE")"

# 如果上游 download.sh 通过 probe 选了具体直链，覆盖 SELECTED_URL
if [[ -n "${VDL_KS_DIRECT_URL:-}" ]]; then
  echo ">>> [kuaishou] Using direct URL from probe selection"
  SELECTED_URL="$VDL_KS_DIRECT_URL"
fi

if [[ -z "$SELECTED_URL" ]]; then
  echo "❌ [kuaishou] No mp4 URL found in share page." >&2
  echo "   This could mean:" >&2
  echo "   1) The link is invalid or expired (kuaishou tokens have TTL)" >&2
  echo "   2) The video is age/region-restricted" >&2
  echo "   3) Kuaishou changed their SSR format (skill needs update)" >&2
  exit 2
fi

# ===== --probe-only: emit JSON with available formats =====
if [[ "$PROBE_ONLY" -eq 1 ]]; then
  PROBE_PY="$(mktemp -t ks-probe.XXXXXX.py)"
  trap 'rm -f "$HTML_TMP" "$PY_SCRIPT" "$PROBE_PY"' EXIT
  cat > "$PROBE_PY" << 'PYEOF'
import re, sys, json, urllib.request
html_path, url_in, photo_id = sys.argv[1], sys.argv[2], sys.argv[3]
html = open(html_path).read()
m = re.search(r'<title>([^<]+)', html)
title = (m.group(1).strip() if m else photo_id)
urls = re.findall(r'https?://[^\s"\']+?\.mp4(?:\?[^\s"\']+)?', html)
seen = {}
for u in urls:
    b = u.split('?')[0]
    if b not in seen: seen[b] = u
UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15"
def head_size(u):
    try:
        req = urllib.request.Request(u, headers={"User-Agent": UA}, method="HEAD")
        with urllib.request.urlopen(req, timeout=8) as r:
            return int(r.headers.get("Content-Length") or 0)
    except Exception:
        return None
def human(n):
    if not n: return None
    n = float(n)
    for u in ['B','KiB','MiB','GiB']:
        if n < 1024: return f"{n:.1f} {u}"
        n /= 1024
def label(u):
    if 'hd15' in u or '_hd' in u: return "HD (高清)"
    if '_b_' in u: return "SD (标清)"
    return "其他"
formats = []
for i, u in enumerate(seen.values()):
    sz = head_size(u)
    formats.append({
        "id": f"ks-{i}",
        "label": label(u),
        "width": None, "height": None, "fps": None,
        "vcodec": "h264", "acodec": "aac",
        "ext": "mp4",
        "filesize": sz,
        "filesize_human": human(sz),
        "tbr": None,
        "note": "hd15" if "hd15" in u else ("_b_" if "_b_" in u else ""),
        "format_arg": u,
    })
formats.sort(key=lambda x: -(x["filesize"] or 0))
print(json.dumps({
    "platform": "kuaishou",
    "url": url_in,
    "title": title or photo_id,
    "uploader": "",
    "upload_date": "",
    "duration": None,
    "thumbnail": "",
    "formats": formats,
}, ensure_ascii=False, indent=2))
PYEOF
  python3 "$PROBE_PY" "$HTML_TMP" "$URL" "$PHOTO_ID"
  exit 0
fi

echo ">>> [kuaishou] Selected stream:"
echo "    ${SELECTED_URL:0:120}..."

OUT_FILE="$OUT_DIR/kuaishou_${PHOTO_ID}.mp4"

# 优先 aria2c (16 路并行)，没有就 curl
if command -v aria2c >/dev/null 2>&1; then
  echo ">>> [kuaishou] Downloading via aria2c (16 connections)..."
  aria2c -x 16 -s 16 -k 1M --max-connection-per-server=16 \
         --file-allocation=none --console-log-level=warn --summary-interval=0 \
         --user-agent="$UA" --allow-overwrite=true \
         -d "$OUT_DIR" -o "kuaishou_${PHOTO_ID}.mp4" \
         "$SELECTED_URL"
else
  echo ">>> [kuaishou] Downloading via curl (single thread)..."
  curl -L -A "$UA" -o "$OUT_FILE" --progress-bar "$SELECTED_URL"
fi

if [[ ! -s "$OUT_FILE" ]]; then
  echo "❌ Download produced empty file" >&2
  exit 3
fi

SIZE="$(ls -lh "$OUT_FILE" | awk '{print $5}')"
echo ""
echo "✅ Saved: $OUT_FILE  ($SIZE)"

# 顺手用 ffprobe 输出基本信息
if command -v ffprobe >/dev/null 2>&1; then
  echo ""
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,codec_name,r_frame_rate \
    -of default=noprint_wrappers=1 "$OUT_FILE"
fi
