#!/usr/bin/env bash
# ===================================================================
# Video Probe — 链接解析（不下载）
# -------------------------------------------------------------------
# 用法：
#   probe.sh <URL>                # 输出 JSON 到 stdout
#   probe.sh --human <URL>        # 输出人类可读表格
#
# 输出 JSON schema：
# {
#   "platform": "youtube|bilibili|douyin|...|generic",
#   "url":      "<input url>",
#   "title":    "<视频标题>",
#   "uploader": "<作者>",
#   "upload_date": "YYYYMMDD",
#   "duration": <秒>,
#   "thumbnail": "<封面 URL>",
#   "formats":  [
#     {
#       "id":             "<format-id>",
#       "label":          "1080p H.264",
#       "width": 1920, "height": 1080,
#       "fps":   30,
#       "vcodec": "avc1.640028", "acodec": "mp4a.40.2",
#       "ext":   "mp4",
#       "filesize":       12345678,
#       "filesize_human": "11.8 MiB",
#       "tbr":            2500,
#       "note":           "<extra info>",
#       "format_arg":     "<给 download.sh format 用的 -f 字符串>"
#     }
#   ]
# }
# ===================================================================
set -euo pipefail

HUMAN=0
if [[ "${1:-}" == "--human" ]]; then HUMAN=1; shift; fi

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "Usage: $0 [--human] <URL>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 平台识别 ----------
PLATFORM="generic"
if   [[ "$URL" =~ youtube\.com|youtu\.be ]]; then PLATFORM="youtube"
elif [[ "$URL" =~ bilibili\.com|b23\.tv ]]; then PLATFORM="bilibili"
elif [[ "$URL" =~ douyin\.com|iesdouyin\.com ]]; then PLATFORM="douyin"
elif [[ "$URL" =~ xiaohongshu\.com|xhslink\.com ]]; then PLATFORM="xiaohongshu"
elif [[ "$URL" =~ kuaishou\.com|gifshow\.com|chenzhongtech\.com ]]; then PLATFORM="kuaishou"
elif [[ "$URL" =~ weibo\.com|weibo\.cn ]]; then PLATFORM="weibo"
elif [[ "$URL" =~ twitter\.com|x\.com ]]; then PLATFORM="twitter"
elif [[ "$URL" =~ vimeo\.com ]]; then PLATFORM="vimeo"
elif [[ "$URL" =~ tiktok\.com ]]; then PLATFORM="tiktok"
fi

YTDLP="$(command -v yt-dlp || true)"

# ---------- Chrome cookies 缓存（与 download.sh 对齐）----------
COOKIE_CACHE_DIR="$HOME/.cache/video-downloader"
CHROME_COOKIES_FILE="$COOKIE_CACHE_DIR/chrome-cookies.txt"
CHROME_COOKIES_MAX_AGE=86400   # 24h

chrome_cookies_fresh() {
  [[ -s "$CHROME_COOKIES_FILE" ]] || return 1
  local age
  age=$(( $(date +%s) - $(stat -f %m "$CHROME_COOKIES_FILE" 2>/dev/null || echo 0) ))
  [[ $age -lt $CHROME_COOKIES_MAX_AGE ]]
}

# 返回 0 表示成功填充 PROBE_COOKIE_ARGS（globally）
PROBE_COOKIE_ARGS=()
ensure_chrome_cookies() {
  if chrome_cookies_fresh; then
    PROBE_COOKIE_ARGS=(--cookies "$CHROME_COOKIES_FILE")
    return 0
  fi
  # 缓存不存在或过期 → 用 --cookies-from-browser 一次（会触发钥匙串），
  # 顺手把 cookies 导出到缓存文件给后续 download.sh 复用
  mkdir -p "$COOKIE_CACHE_DIR"
  echo ">>> [probe] Reading Chrome cookies (may prompt Keychain ONCE)" >&2
  if "$YTDLP" --cookies-from-browser chrome --cookies "$CHROME_COOKIES_FILE" \
        --skip-download --no-warnings -O "ok" \
        "https://www.bilibili.com" >/dev/null 2>&1 && [[ -s "$CHROME_COOKIES_FILE" ]]; then
    PROBE_COOKIE_ARGS=(--cookies "$CHROME_COOKIES_FILE")
    return 0
  fi
  # 失败：回退到 cookies-from-browser 直读模式
  PROBE_COOKIE_ARGS=(--cookies-from-browser chrome)
  return 0
}

# ---------- 委派到平台专用 probe ----------
probe_douyin() {
  bash "$SCRIPT_DIR/download-douyin.sh" --probe-only "$URL"
}
probe_kuaishou() {
  bash "$SCRIPT_DIR/download-kuaishou.sh" --probe-only "$URL"
}

# ---------- yt-dlp 通用 probe ----------
probe_ytdlp() {
  [[ -z "$YTDLP" ]] && { echo '{"error":"yt-dlp not installed"}'; return 1; }

  # 平台特定的 cookies / extractor 参数（与 download.sh 对齐）
  # 默认全部 guest 模式；要解锁登录态档位必须显式 VDL_USE_CHROME=1
  local extra_args=()
  case "$PLATFORM" in
    youtube)
      extra_args+=(--extractor-args "youtube:player_client=ios,web_safari")
      if [[ "${VDL_USE_CHROME:-}" == "1" ]]; then
        ensure_chrome_cookies
        extra_args+=("${PROBE_COOKIE_ARGS[@]}")
      fi
      ;;
    xiaohongshu|bilibili)
      # B 站 / 小红书：仅在 VDL_USE_CHROME=1 时读 Chrome cookies（避免静默弹钥匙串）
      if [[ "${VDL_USE_CHROME:-}" == "1" ]]; then
        ensure_chrome_cookies
        extra_args+=("${PROBE_COOKIE_ARGS[@]}")
      else
        echo ">>> [probe] $PLATFORM guest mode (HD/4K hidden). To unlock: VDL_USE_CHROME=1 bash $0 ..." >&2
      fi
      ;;
  esac

  # -J = single JSON dump
  "$YTDLP" -J --no-warnings --no-playlist ${extra_args[@]+"${extra_args[@]}"} "$URL" 2>/dev/null \
    | python3 "$SCRIPT_DIR/_probe_format_ytdlp.py" "$PLATFORM" "$URL"
}

# ---------- 路由 ----------
JSON=""
case "$PLATFORM" in
  douyin)   JSON="$(probe_douyin)" ;;
  kuaishou) JSON="$(probe_kuaishou)" ;;
  *)        JSON="$(probe_ytdlp)" ;;
esac

if [[ -z "$JSON" || "$JSON" == "null" ]]; then
  echo '{"error":"probe failed (empty result)"}' >&2
  exit 2
fi

# ---------- 输出 ----------
if [[ "$HUMAN" -eq 0 ]]; then
  printf '%s\n' "$JSON"
  exit 0
fi

# 人类可读模式
python3 "$SCRIPT_DIR/_probe_render_human.py" <<<"$JSON"
