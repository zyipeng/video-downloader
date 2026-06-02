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
  local extra_args=()
  case "$PLATFORM" in
    youtube)
      extra_args+=(--extractor-args "youtube:player_client=ios,web_safari")
      ;;
    xiaohongshu)
      # 4K 需要 chrome 的 web_session cookie
      local cookies_file="$HOME/.cache/video-downloader/chrome-cookies.txt"
      if [[ -s "$cookies_file" ]]; then
        extra_args+=(--cookies "$cookies_file")
      fi
      ;;
    bilibili)
      local cookies_file="$HOME/.cache/video-downloader/chrome-cookies.txt"
      if [[ -s "$cookies_file" ]]; then
        extra_args+=(--cookies "$cookies_file")
      fi
      ;;
  esac

  # -J = single JSON dump
  "$YTDLP" -J --no-warnings --no-playlist "${extra_args[@]}" "$URL" 2>/dev/null \
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
