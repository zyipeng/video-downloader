#!/usr/bin/env bash
# Douyin (抖音) downloader using SSR share-page API
# Bypasses yt-dlp built-in extractor (broken since 2025 anti-bot update)
# Usage: download-douyin.sh <quality|speed|compat> <URL> [output_dir]

set -e

# ===== --probe-only mode =====
PROBE_ONLY=0
if [[ "${1:-}" == "--probe-only" ]]; then
  PROBE_ONLY=1
  shift
fi

# ===== --ratio <value> mode (用户直接指定 ratio，用于显式 format 选择) =====
EXPLICIT_RATIO=""
if [[ "${1:-}" == "--ratio" ]]; then
  EXPLICIT_RATIO="$2"
  shift 2
fi

MODE="${1:-compat}"
URL="${2:-}"
OUT_DIR="${3:-$HOME/Downloads}"

if [[ -z "$URL" ]]; then
  echo "Usage: $0 [--probe-only|--ratio <r>] <quality|speed|compat> <URL> [output_dir]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

UA_IOS="Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

# --- Step 1: resolve short link -> aweme_id ---
echo ">>> Resolving Douyin URL: $URL"

AWEME_ID=""
# Pattern A: v.douyin.com/xxx 短链
if [[ "$URL" =~ v\.douyin\.com|iesdouyin\.com ]]; then
  REDIRECT_URL="$(curl -sIL "$URL" -A "$UA_IOS" 2>/dev/null | awk -F': ' 'tolower($1)=="location" {print $2}' | tail -1 | tr -d '\r\n')"
  echo "    redirect -> $REDIRECT_URL"
  AWEME_ID="$(echo "$REDIRECT_URL" | grep -oE '/(video|share/video)/[0-9]+' | grep -oE '[0-9]+' | head -1)"
fi

# Pattern B: www.douyin.com/video/xxx 完整链接
if [[ -z "$AWEME_ID" ]]; then
  AWEME_ID="$(echo "$URL" | grep -oE '/(video|share/video)/[0-9]+' | grep -oE '[0-9]+' | head -1)"
fi

# Pattern C: ?modal_id=xxx
if [[ -z "$AWEME_ID" ]]; then
  AWEME_ID="$(echo "$URL" | grep -oE 'modal_id=[0-9]+' | grep -oE '[0-9]+' | head -1)"
fi

if [[ -z "$AWEME_ID" ]]; then
  echo "ERROR: cannot extract aweme_id from URL: $URL" >&2
  exit 3
fi

echo "    aweme_id = $AWEME_ID"

# --- Step 2: fetch SSR share page ---
SHARE_URL="https://www.iesdouyin.com/share/video/${AWEME_ID}/"
TMP_HTML="$(mktemp -t douyin_XXXXXX.html)"
trap 'rm -f "$TMP_HTML"' EXIT

echo ">>> Fetching share page: $SHARE_URL"
curl -sL -A "$UA_IOS" "$SHARE_URL" -o "$TMP_HTML"

if [[ ! -s "$TMP_HTML" ]]; then
  echo "ERROR: empty response from $SHARE_URL" >&2
  exit 4
fi

# --- Step 3: extract title + play_addr URL ---
TITLE="$(python3 -c "
import re, sys, html
data = open('$TMP_HTML', 'r', encoding='utf-8', errors='replace').read()
m = re.search(r'<title[^>]*>([^<]+)</title>', data)
if m:
    t = html.unescape(m.group(1)).strip()
    t = re.sub(r'[/\\\\:*?\"<>|]', '_', t)
    t = t[:120]
    print(t)
" 2>/dev/null)"

if [[ -z "$TITLE" ]]; then
  TITLE="douyin_${AWEME_ID}"
fi

# Extract play_addr URL — prefer 'play' (no watermark) over 'playwm' if available
PLAY_URL="$(python3 -c "
import re, json, sys
data = open('$TMP_HTML', 'r', encoding='utf-8', errors='replace').read()
# raw play_addr block
m = re.search(r'\"play_addr\"\s*:\s*\{([^}]+)\}', data)
if not m:
    sys.exit(1)
block = m.group(1)
urls = re.findall(r'https?[^\"]+', block)
urls = [u.replace('\\\\u002F', '/').replace('\\\\/', '/') for u in urls]
# Prefer non-watermark playwm -> play if possible
preferred = None
for u in urls:
    if 'playwm' not in u and 'watermark' not in u:
        preferred = u; break
if not preferred:
    preferred = urls[0] if urls else ''
print(preferred)
" 2>/dev/null)"

if [[ -z "$PLAY_URL" ]]; then
  echo "ERROR: cannot find play_addr in share page" >&2
  echo "       (Douyin may have changed page structure; check $TMP_HTML)" >&2
  exit 5
fi

# ===== --probe-only: emit JSON of available formats =====
if [[ "$PROBE_ONLY" -eq 1 ]]; then
  # 抖音 SSR 给出三档「逻辑画质」：通过修改 /play/?ratio= 实现
  # 大小未知（API 不返回 Content-Length without HEAD），我们用 HEAD 探一下
  PLAY_URL_BASE="${PLAY_URL//playwm/play}"
  probe_size() {
    local ratio="$1"
    local u="$PLAY_URL_BASE"
    if [[ "$u" == *"ratio="* ]]; then
      u="$(echo "$u" | sed -E "s/ratio=[a-zA-Z0-9]+/ratio=${ratio}/")"
    else
      local sep="?"; [[ "$u" == *\?* ]] && sep="&"
      u="${u}${sep}ratio=${ratio}"
    fi
    curl -sI -A "$UA_IOS" --max-time 8 "$u" 2>/dev/null \
      | awk -F': ' 'tolower($1)=="content-length" {print $2}' \
      | tr -d '\r\n' | tail -1
  }
  SZ_720=$(probe_size 720p)
  SZ_1080=$(probe_size 1080p)
  SZ_DEF=$(probe_size default)

  python3 - "$AWEME_ID" "$TITLE" "$URL" "$SZ_720" "$SZ_1080" "$SZ_DEF" <<'PY'
import sys, json
aweme, title, url, s720, s1080, sdef = sys.argv[1:7]
def to_int(x):
    try: return int(x) if x else None
    except: return None
def human(n):
    if not n: return None
    n = float(n)
    for u in ['B','KiB','MiB','GiB']:
        if n < 1024: return f"{n:.1f} {u}"
        n /= 1024
def mk(ratio, label, note, sz):
    s = to_int(sz)
    return {
        "id": f"ratio={ratio}",
        "label": label,
        "width": None, "height": None, "fps": None,
        "vcodec": "h264" if ratio != "default" else "?",
        "acodec": "aac",
        "ext": "mp4",
        "filesize": s,
        "filesize_human": human(s),
        "tbr": None,
        "note": note,
        "format_arg": ratio,  # download.sh 把这值传给 download-douyin.sh --ratio
    }
formats = [
    mk("default", "原画 master", "上传者原始文件（可能 4K60 HEVC）", sdef),
    mk("1080p",  "1080p",       "H.264 转码（任意播放器兼容）",     s1080),
    mk("720p",   "720p",        "H.264 转码（体积最小）",           s720),
]
print(json.dumps({
    "platform": "douyin",
    "url": url,
    "title": title,
    "uploader": "",
    "upload_date": "",
    "duration": None,
    "thumbnail": "",
    "formats": formats,
}, ensure_ascii=False, indent=2))
PY
  exit 0
fi

# Mode handling — Douyin share API hidden tricks:
#   /playwm/                    -> always 720p H.264 + watermark (ratio param ignored)
#   /play/?ratio=720p|1080p     -> fixed-bitrate H.264 transcode (max 1080p)
#   /play/?ratio=default        -> ORIGINAL MASTER FILE (could be 4K HEVC, 1080p H.264, etc.)
#                                  This is the only way to get 4K/60fps if the uploader provided it.
# All undocumented but stable (used by 3rd-party downloader sites like aitoolwang).

if [[ -n "$EXPLICIT_RATIO" ]]; then
  # 用户通过 --ratio 显式指定（来自 probe → 用户选择 → download --format）
  TARGET_RATIO="$EXPLICIT_RATIO"
  EXTRA_NOTE="(user-selected ratio=$TARGET_RATIO)"
else
  # 旧模式自动映射
  case "$MODE" in
    speed)
      TARGET_RATIO="720p"
      EXTRA_NOTE="(speed: 720p H.264, smaller file)"
      ;;
    quality)
      TARGET_RATIO="default"
      EXTRA_NOTE="(quality: ratio=default -> original master, may be 4K60 HEVC if uploader provided)"
      ;;
    compat|*)
      TARGET_RATIO="1080p"
      EXTRA_NOTE="(compat: 1080p H.264 + AAC, universal player support)"
      ;;
  esac
fi

# Try to convert playwm -> play to drop watermark, and rewrite ratio param
NOWM_URL="${PLAY_URL//playwm/play}"
# Rewrite ratio=... -> ratio=$TARGET_RATIO (default API ships ratio=720p)
if [[ "$NOWM_URL" == *"ratio="* ]]; then
  NOWM_URL="$(echo "$NOWM_URL" | sed -E "s/ratio=[a-zA-Z0-9]+/ratio=${TARGET_RATIO}/")"
else
  # If no ratio param, append one
  SEP="?"; [[ "$NOWM_URL" == *\?* ]] && SEP="&"
  NOWM_URL="${NOWM_URL}${SEP}ratio=${TARGET_RATIO}"
fi
echo "    target ratio = $TARGET_RATIO"
echo "    final URL    = $NOWM_URL"

OUT_FILE="$OUT_DIR/${TITLE}.mp4"

echo "============================================"
echo " Douyin Downloader"
echo " mode    : $MODE  $EXTRA_NOTE"
echo " title   : $TITLE"
echo " out_file: $OUT_FILE"
echo "============================================"

# --- Step 4: download (try no-watermark first, fallback to watermark) ---
download_to() {
  local url="$1"
  local out="$2"
  if command -v aria2c >/dev/null 2>&1; then
    aria2c --console-log-level=warn -x 16 -s 16 -k 1M --file-allocation=none \
           -U "$UA_IOS" -d "$(dirname "$out")" -o "$(basename "$out")" \
           --allow-overwrite=true "$url"
  else
    curl -L -A "$UA_IOS" -o "$out" "$url"
  fi
}

echo ">>> Trying no-watermark URL..."
if download_to "$NOWM_URL" "$OUT_FILE" 2>&1; then
  if [[ -s "$OUT_FILE" ]]; then
    SIZE_BYTES="$(stat -f%z "$OUT_FILE" 2>/dev/null || stat -c%s "$OUT_FILE")"
    if [[ "$SIZE_BYTES" -gt 100000 ]]; then
      echo ">>> Got no-watermark version."
    else
      echo ">>> No-watermark too small ($SIZE_BYTES bytes), retrying with watermark URL..."
      download_to "$PLAY_URL" "$OUT_FILE"
    fi
  fi
else
  echo ">>> No-watermark failed, retrying with watermark URL..."
  download_to "$PLAY_URL" "$OUT_FILE"
fi

# --- Step 5: report ---
echo ""
echo "============================================"
echo " Download complete."
echo "============================================"
SIZE="$(ls -lh "$OUT_FILE" | awk '{print $5}')"
echo " file : $OUT_FILE"
echo " size : $SIZE"
if command -v ffprobe >/dev/null 2>&1; then
  echo " info :"
  ffprobe -v error -show_entries stream=codec_name,codec_type,width,height \
          -of default=noprint_wrappers=1 "$OUT_FILE" 2>/dev/null | sed 's/^/        /'
fi
