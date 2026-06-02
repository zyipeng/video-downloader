#!/usr/bin/env bash
# Video Downloader - unified entry point
# Supports YouTube, Bilibili, Twitter, Vimeo, Weibo, TikTok and 1700+ sites via yt-dlp
# Usage: download.sh <quality|speed|compat> <URL> [output_dir]

set -e

# ===================================================================
# Arg parsing
# 兼容两种调用语法：
#   旧：download.sh <quality|speed|compat>           <URL> [out_dir]
#   新：download.sh --format-id <id>                 <URL> [out_dir]
#       download.sh --format    <#row>               <URL> [out_dir]   (按 probe 表行号)
#       download.sh --format-arg "<-f expr>"         <URL> [out_dir]   (直接传 yt-dlp -f)
# ===================================================================
MODE=""
FORMAT_OVERRIDE=""        # 直接传 yt-dlp 的 -f 表达式
FORMAT_ROW=""             # probe 输出里的行号
FORMAT_ID=""              # 直接给 format-id

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format-id)   FORMAT_ID="$2"; shift 2 ;;
    --format)      FORMAT_ROW="$2"; shift 2 ;;
    --format-arg)  FORMAT_OVERRIDE="$2"; shift 2 ;;
    quality|speed|compat) MODE="$1"; shift ;;
    *) break ;;
  esac
done

URL="${1:-}"
OUT_DIR="${2:-$HOME/Downloads}"
MODE="${MODE:-compat}"

if [[ -z "$URL" ]]; then
  cat >&2 <<EOF
Usage:
  $0 <quality|speed|compat> <URL> [output_dir]
  $0 --format-id <id>       <URL> [output_dir]
  $0 --format    <row>      <URL> [output_dir]   # row number from probe.sh --human
  $0 --format-arg "<expr>"  <URL> [output_dir]   # raw yt-dlp -f expression

Hint: run \`bash scripts/probe.sh --human <URL>\` first to see all formats.
EOF
  exit 1
fi

# 把 probe 表行号解析成 format-id
SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "$FORMAT_ROW" ]]; then
  echo ">>> Probing for format row #$FORMAT_ROW ..."
  PROBE_JSON="$(bash "$SCRIPT_DIR_EARLY/probe.sh" "$URL" 2>/dev/null || true)"
  if [[ -z "$PROBE_JSON" ]]; then
    echo "ERROR: probe failed; cannot resolve --format $FORMAT_ROW" >&2
    exit 1
  fi
  FORMAT_OVERRIDE="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
i = int('$FORMAT_ROW')
fmts = d.get('formats', [])
if i < 0 or i >= len(fmts):
    sys.exit(2)
print(fmts[i].get('format_arg') or fmts[i].get('id'))
" "$PROBE_JSON")" || { echo "ERROR: row #$FORMAT_ROW out of range" >&2; exit 1; }
  echo ">>> Resolved row #$FORMAT_ROW -> -f $FORMAT_OVERRIDE"
fi

if [[ -n "$FORMAT_ID" && -z "$FORMAT_OVERRIDE" ]]; then
  FORMAT_OVERRIDE="$FORMAT_ID"
fi

# --- Detect platform ---
PLATFORM="generic"
if [[ "$URL" =~ youtube\.com|youtu\.be ]]; then
  PLATFORM="youtube"
elif [[ "$URL" =~ bilibili\.com|b23\.tv ]]; then
  PLATFORM="bilibili"
elif [[ "$URL" =~ twitter\.com|x\.com ]]; then
  PLATFORM="twitter"
elif [[ "$URL" =~ vimeo\.com ]]; then
  PLATFORM="vimeo"
elif [[ "$URL" =~ weibo\.com|weibo\.cn ]]; then
  PLATFORM="weibo"
elif [[ "$URL" =~ douyin\.com|iesdouyin\.com ]]; then
  PLATFORM="douyin"
elif [[ "$URL" =~ xiaohongshu\.com|xhslink\.com ]]; then
  PLATFORM="xiaohongshu"
elif [[ "$URL" =~ tiktok\.com ]]; then
  PLATFORM="tiktok"
elif [[ "$URL" =~ kuaishou\.com|gifshow\.com|chenzhongtech\.com ]]; then
  PLATFORM="kuaishou"
fi

# --- Douyin: delegate to specialized script (yt-dlp built-in extractor is broken) ---
if [[ "$PLATFORM" == "douyin" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DOUYIN_SCRIPT="$SCRIPT_DIR/download-douyin.sh"
  if [[ -x "$DOUYIN_SCRIPT" ]]; then
    echo ">>> Detected Douyin URL, delegating to download-douyin.sh"
    if [[ -n "$FORMAT_OVERRIDE" ]]; then
      exec bash "$DOUYIN_SCRIPT" --ratio "$FORMAT_OVERRIDE" "$URL" "$OUT_DIR"
    fi
    exec bash "$DOUYIN_SCRIPT" "$MODE" "$URL" "$OUT_DIR"
  else
    echo "ERROR: Douyin script not found or not executable: $DOUYIN_SCRIPT" >&2
    exit 6
  fi
fi

# --- Kuaishou: delegate to specialized script (yt-dlp has no built-in extractor) ---
if [[ "$PLATFORM" == "kuaishou" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  KS_SCRIPT="$SCRIPT_DIR/download-kuaishou.sh"
  if [[ -x "$KS_SCRIPT" ]]; then
    echo ">>> Detected Kuaishou URL, delegating to download-kuaishou.sh"
    # 如果用户通过 probe 选了具体格式，FORMAT_OVERRIDE 是直接的 mp4 URL
    if [[ "$FORMAT_OVERRIDE" =~ ^https?:// ]]; then
      # 把直链塞给 kuaishou 脚本（用 env 变量）
      VDL_KS_DIRECT_URL="$FORMAT_OVERRIDE" exec bash "$KS_SCRIPT" "$MODE" "$URL" "$OUT_DIR"
    fi
    exec bash "$KS_SCRIPT" "$MODE" "$URL" "$OUT_DIR"
  else
    echo "ERROR: Kuaishou script not found or not executable: $KS_SCRIPT" >&2
    exit 7
  fi
fi

# --- Locate binaries ---
YTDLP="$(command -v yt-dlp || true)"
FFMPEG="$(command -v ffmpeg || true)"
ARIA2C="$(command -v aria2c || true)"
BREW="$(command -v brew || true)"

install_with_brew() {
  local pkg="$1"
  if [[ -z "$BREW" ]]; then
    echo "ERROR: Homebrew not found. Please install $pkg manually (or run: pip3 install -U $pkg)." >&2
    return 1
  fi
  echo ">>> Installing $pkg via Homebrew..."
  "$BREW" install "$pkg"
}

if [[ -z "$YTDLP" ]]; then
  install_with_brew yt-dlp
  YTDLP="$(command -v yt-dlp || true)"
fi
if [[ -z "$FFMPEG" ]]; then
  install_with_brew ffmpeg
  FFMPEG="$(command -v ffmpeg || true)"
fi
if [[ -z "$ARIA2C" && -n "$BREW" ]]; then
  echo ">>> aria2 not found, installing for parallel download..."
  "$BREW" install aria2 2>/dev/null || true
  ARIA2C="$(command -v aria2c || true)"
fi

# --- Build mode-specific format selector ---
FORMAT=""
MERGE_FORMAT="mp4"
EXTRA_NOTE=""

case "$MODE" in
  quality)
    FORMAT="bv*+ba/b"
    MERGE_FORMAT="mkv"
    EXTRA_NOTE="(quality: max bitrate, may be AV1/HEVC; needs modern player like IINA/VLC/PotPlayer)"
    ;;
  speed)
    FORMAT="bv*[height<=480][ext=mp4]+ba[ext=m4a]/b[height<=480][ext=mp4]/bv*[height<=480]+ba/b[height<=480]"
    MERGE_FORMAT="mp4"
    EXTRA_NOTE="(speed: <=480p, small + fast)"
    ;;
  compat)
    FORMAT="bv*[vcodec^=avc1][height<=1080]+ba/b[ext=mp4][height<=1080]"
    MERGE_FORMAT="mp4"
    EXTRA_NOTE="(compat: <=1080p H.264+AAC, universal player support)"
    ;;
  *)
    echo "ERROR: unknown mode '$MODE'. Use quality | speed | compat." >&2
    exit 2
    ;;
esac

# 用户显式选了 format → 覆盖 mode 选择器
if [[ -n "$FORMAT_OVERRIDE" ]]; then
  FORMAT="$FORMAT_OVERRIDE"
  MERGE_FORMAT="mp4"
  EXTRA_NOTE="(user-selected format: $FORMAT_OVERRIDE)"
fi

echo "============================================"
echo " Video Downloader"
echo " platform: $PLATFORM"
echo " mode    : $MODE  $EXTRA_NOTE"
echo " url     : $URL"
echo " out_dir : $OUT_DIR"
echo "============================================"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

# 平台特定 FORMAT 覆盖只在用户没显式指定时生效
PLATFORM_ARGS=()
case "$PLATFORM" in
  youtube)
    PLATFORM_ARGS+=(--extractor-args "youtube:player_client=ios,web_safari")
    ;;
  bilibili)
    # B 站 720P+ 必须登录，下面会尝试自动读取浏览器 cookies
    :
    ;;
  xiaohongshu)
    # 小红书返回单流 MP4（视频+音频已合并），不是分离 DASH 流
    # 注意：yt-dlp 给小红书报的 vcodec 是 "h264" / "hevc"（小写），不是 "avc1" / "hev1"
    if [[ -z "$FORMAT_OVERRIDE" ]]; then
      case "$MODE" in
        quality)
          FORMAT="b"
          ;;
        speed)
          FORMAT="worst[ext=mp4]/worst"
          ;;
        compat)
          FORMAT="b[vcodec*=h264]/b[vcodec*=avc]/b[ext=mp4]/b"
          ;;
      esac
      MERGE_FORMAT="mp4"
      EXTRA_NOTE="$EXTRA_NOTE [xhs: single-stream]"
    fi
    ;;
esac

# --- Common args (must come AFTER platform-specific FORMAT override) ---
COMMON_ARGS=(
  -f "$FORMAT"
  --merge-output-format "$MERGE_FORMAT"
  --concurrent-fragments 16
  --http-chunk-size 10M
  --retries 10
  --fragment-retries 10
  --no-mtime
  -o "%(title).200B [%(id)s].%(ext)s"
)

# --- Try cookies from browser (with caching to avoid repeated Keychain prompts) ---
#
# 关键背景：每次执行 `yt-dlp --cookies-from-browser chrome` 都会触发一次 macOS
# Keychain 弹窗（"security 想要使用 Chrome Safe Storage"），用来解密 v10 加密的
# cookies。这是 macOS 安全模型强制，无法绕过——除非：
#   1) 在弹窗时点"始终允许"（不是"允许"！把 security 加到 ACL 白名单）
#   2) 把 cookies 一次性导出成 netscape 文件，后续用 --cookies <file>，绕开 security
#
# 我们采用方案 2：**一次导出，永久免弹**
#   - 第一次需要 chrome cookies 时，弹一次窗 → 立刻导出到本地文件
#   - 后续直接读文件，永远不再调 --cookies-from-browser
#   - 文件 24 小时刷新一次（或用户手动 rm 重置）
#
# 控制变量：
#   - VDL_BROWSER=safari|firefox|chrome  显式指定浏览器（safari/firefox 不需 keychain）
#   - VDL_USE_CHROME=1                   强制使用 Chrome（即使平台不需登录）
#   - rm ~/.cache/video-downloader/chrome-cookies.txt   重置 chrome cookies 文件
#   - rm ~/.cache/video-downloader/cookies.cache        重置浏览器选择缓存
#
COOKIE_CACHE_DIR="$HOME/.cache/video-downloader"
COOKIE_CACHE_FILE="$COOKIE_CACHE_DIR/cookies.cache"
CHROME_COOKIES_FILE="$COOKIE_CACHE_DIR/chrome-cookies.txt"
mkdir -p "$COOKIE_CACHE_DIR"
chmod 700 "$COOKIE_CACHE_DIR"

# Chrome cookies 文件 24 小时刷新一次
CHROME_COOKIES_MAX_AGE=86400

# 导出 chrome cookies 到本地文件（弹一次钥匙串，之后永久免弹）
export_chrome_cookies() {
  local target="$1"
  echo ">>> First-time Chrome cookies export (will prompt Keychain ONCE)"
  echo "    💡 Click \"Always Allow\" (NOT \"Allow\") to skip future prompts"
  echo "       (\"始终允许\" instead of \"允许\")"
  echo ""
  if "$YTDLP" --cookies-from-browser chrome \
       --cookies "$target" \
       --skip-download --no-warnings \
       "https://www.xiaohongshu.com/" 2>&1 | grep -E "Extracted|ERROR" | head -3; then
    if [[ -s "$target" ]]; then
      chmod 600 "$target"
      echo ">>> ✅ Cookies exported to $target"
      echo "    Future runs will read this file (no Keychain prompts)"
      return 0
    fi
  fi
  echo ">>> ❌ Export failed (user denied or no cookies)"
  return 1
}

# 检查 chrome cookies 文件是否仍然新鲜（< 24h）
chrome_cookies_fresh() {
  [[ -f "$CHROME_COOKIES_FILE" && -s "$CHROME_COOKIES_FILE" ]] || return 1
  local age
  age=$(( $(date +%s) - $(stat -f %m "$CHROME_COOKIES_FILE" 2>/dev/null || echo 0) ))
  [[ $age -lt $CHROME_COOKIES_MAX_AGE ]]
}

COOKIE_ARGS=()

# 平台对登录态的依赖
NEEDS_LOGIN="no"
case "$PLATFORM" in
  bilibili)
    # B 站 720P+ 必须登录
    NEEDS_LOGIN="yes"
    ;;
  xiaohongshu)
    # 小红书：游客 720p；要 4K/1440p/1080p HEVC 必须登录态 web_session cookie
    if [[ "$MODE" == "quality" ]]; then
      NEEDS_LOGIN="yes"
    fi
    ;;
esac

# 选择 cookies 来源
if [[ "$NEEDS_LOGIN" == "no" && -z "$VDL_BROWSER" && "$VDL_USE_CHROME" != "1" ]]; then
  # 不需要登录的平台：完全 guest 模式
  echo ">>> Guest mode for $PLATFORM (no cookies needed)"
  echo "    (override: VDL_BROWSER=chrome|safari|firefox)"

elif [[ -n "$VDL_BROWSER" && "$VDL_BROWSER" != "chrome" ]]; then
  # 用户指定非 chrome 浏览器：直接用 --cookies-from-browser（safari/firefox 不需 keychain）
  COOKIE_ARGS=(--cookies-from-browser "$VDL_BROWSER")
  echo ">>> Using cookies from $VDL_BROWSER (no keychain needed)"

else
  # 走到这里：需要 chrome cookies（NEEDS_LOGIN=yes 或 VDL_USE_CHROME=1 或 VDL_BROWSER=chrome）
  # 优先级：本地文件 > 重新导出
  if chrome_cookies_fresh; then
    COOKIE_ARGS=(--cookies "$CHROME_COOKIES_FILE")
    AGE_HOURS=$(( ($(date +%s) - $(stat -f %m "$CHROME_COOKIES_FILE")) / 3600 ))
    echo ">>> Using exported Chrome cookies (${AGE_HOURS}h old, no keychain prompt)"
    echo "    refresh: rm $CHROME_COOKIES_FILE"
  else
    # 文件不在或过期 → 弹一次钥匙串导出
    echo ">>> Chrome cookies need refresh (will prompt Keychain ONCE)"
    if export_chrome_cookies "$CHROME_COOKIES_FILE"; then
      COOKIE_ARGS=(--cookies "$CHROME_COOKIES_FILE")
    else
      echo ">>> Falling back to guest mode"
      COOKIE_ARGS=()
    fi
  fi
fi

# 4) 平台特定的登录提示
if [[ ${#COOKIE_ARGS[@]} -eq 0 && "$NEEDS_LOGIN" == "yes" ]]; then
  if [[ "$PLATFORM" == "bilibili" ]]; then
    echo "    ⚠️  Bilibili guest mode: 720P+ NOT available."
    echo "        For HD: VDL_USE_CHROME=1 bash $0 ..."
  fi
  if [[ "$PLATFORM" == "xiaohongshu" ]]; then
    echo "    ⚠️  Xiaohongshu guest mode: may fail on private notes."
    echo "        For login: VDL_USE_CHROME=1 bash $0 ..."
  fi
fi

# --- aria2c args (when available) ---
DOWNLOADER_ARGS=()
if [[ -n "$ARIA2C" ]]; then
  DOWNLOADER_ARGS=(
    --downloader aria2c
    --downloader-args "aria2c:-x 16 -s 16 -k 1M --max-connection-per-server=16 --min-split-size=1M --file-allocation=none --console-log-level=warn"
  )
  echo ">>> Using aria2c with 16 parallel connections"
fi

# --- Run (tee stderr so we can give error-specific hints) ---
echo ">>> Starting download..."
echo ""
ERR_LOG="$(mktemp -t vdl-err.XXXXXX)"
trap 'rm -f "$ERR_LOG"' EXIT

set +e
"$YTDLP" \
  "${COMMON_ARGS[@]}" \
  "${PLATFORM_ARGS[@]}" \
  "${COOKIE_ARGS[@]}" \
  "${DOWNLOADER_ARGS[@]}" \
  "$URL" 2> >(tee "$ERR_LOG" >&2)
DL_EXIT=$?
set -e

echo ""
if [[ $DL_EXIT -eq 0 ]]; then
  echo "============================================"
  echo " Download complete."
  echo "============================================"
  LATEST="$(ls -t "$OUT_DIR" 2>/dev/null | head -1)"
  if [[ -n "$LATEST" ]]; then
    FULL="$OUT_DIR/$LATEST"
    SIZE="$(ls -lh "$FULL" | awk '{print $5}')"
    echo " file : $FULL"
    echo " size : $SIZE"
    if command -v ffprobe >/dev/null 2>&1; then
      echo " info :"
      ffprobe -v error -show_entries stream=codec_name,codec_type,width,height \
              -of default=noprint_wrappers=1 "$FULL" 2>/dev/null | sed 's/^/        /'
    fi
  fi
else
  echo "" >&2
  echo "ERROR: yt-dlp exited with code $DL_EXIT" >&2
  echo "--------------------------------------------" >&2

  # --- Error attribution: parse stderr for known patterns ---
  STDERR_TEXT="$(cat "$ERR_LOG" 2>/dev/null || true)"

  if echo "$STDERR_TEXT" | grep -qiE "Unable to extract initial state|verify you are a human|please solve the captcha"; then
    echo " 🛑 Anti-scraping CAPTCHA triggered." >&2
    echo "    → Open the URL in your browser, solve the CAPTCHA, then retry." >&2
  elif echo "$STDERR_TEXT" | grep -qiE "No video formats found|requested format is not available"; then
    if [[ "$PLATFORM" == "xiaohongshu" ]]; then
      echo " 🛑 No video formats found on Xiaohongshu." >&2
      echo "    → Make sure you're LOGGED IN to xiaohongshu.com in Chrome." >&2
      echo "    → Use a complete share link (with xsec_token) — copy from the App's share button." >&2
    elif [[ "$PLATFORM" == "bilibili" ]]; then
      echo " 🛑 No HD formats. Bilibili 720P+ requires login (NOT premium)." >&2
      echo "    → Open bilibili.com in Chrome, log in, then retry." >&2
    else
      echo " 🛑 No matching formats found." >&2
      echo "    → Try a different mode (quality | speed | compat)." >&2
    fi
  elif echo "$STDERR_TEXT" | grep -qiE "HTTP Error 401|HTTP Error 403|Sign in to confirm|requires authentication"; then
    echo " 🛑 Authentication / token issue (401/403)." >&2
    if [[ "$PLATFORM" == "xiaohongshu" ]]; then
      echo "    → The xsec_token in your URL has expired." >&2
      echo "    → Re-copy a fresh share link from the Xiaohongshu App." >&2
    else
      echo "    → Log in to the platform in your browser, then retry." >&2
    fi
  elif echo "$STDERR_TEXT" | grep -qiE "Video unavailable|removed by the user|private video"; then
    echo " 🛑 Video unavailable, removed, or private." >&2
  elif echo "$STDERR_TEXT" | grep -qiE "Unsupported URL|No suitable extractor"; then
    echo " 🛑 URL pattern not recognized by yt-dlp." >&2
    echo "    → Check the URL, or update yt-dlp: brew upgrade yt-dlp" >&2
  fi

  exit "$DL_EXIT"
fi
