#!/bin/bash
# Build SafariMRUTabs.app
#
#   bash build.sh            # ký bằng chứng chỉ sẵn có — quyền Accessibility giữ nguyên qua các lần build
#   bash build.sh --adhoc    # ký ad-hoc — dùng khi build để gửi cho máy khác
#   bash build.sh --install  # build xong chép luôn vào /Applications và mở

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

NAME="SafariMRUTabs"
BUILD="build"
APP="$BUILD/$NAME.app"
MIN_MACOS="13.0"

ADHOC=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --adhoc)   ADHOC=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Tham số lạ: $arg"; exit 1 ;;
  esac
done

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }

command -v swiftc >/dev/null || die "chưa có swiftc. Cài Xcode hoặc: xcode-select --install"

# ── 1. Biên dịch (universal: Apple Silicon + Intel) ───────────────────────
say "1/4  Biên dịch"
rm -rf "$BUILD"
mkdir -p "$BUILD"

FRAMEWORKS=(-framework Cocoa -framework Carbon -framework ApplicationServices -framework ServiceManagement)
SLICES=()
for ARCH in arm64 x86_64; do
  OUT="$BUILD/$NAME-$ARCH"
  if swiftc -swift-version 5 -O \
      -target "$ARCH-apple-macos$MIN_MACOS" \
      -o "$OUT" Sources/*.swift "${FRAMEWORKS[@]}" 2>"$BUILD/$ARCH.log"; then
    ok "$ARCH"
    SLICES+=("$OUT")
  else
    if [ "$ARCH" = "arm64" ]; then
      cat "$BUILD/$ARCH.log"
      die "biên dịch arm64 thất bại"
    fi
    warn "$ARCH bỏ qua (xem $BUILD/$ARCH.log) — app sẽ chỉ chạy trên Apple Silicon"
  fi
done
[ ${#SLICES[@]} -gt 0 ] || die "không tạo được binary nào"

# ── 2. Đóng gói .app ──────────────────────────────────────────────────────
say "2/4  Đóng gói"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ${#SLICES[@]} -gt 1 ]; then
  lipo -create -output "$APP/Contents/MacOS/$NAME" "${SLICES[@]}" || die "lipo thất bại"
  ok "universal (arm64 + x86_64)"
else
  cp "${SLICES[0]}" "$APP/Contents/MacOS/$NAME"
  ok "một kiến trúc"
fi
chmod +x "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
rm -f "${SLICES[@]}"
ok "$APP"

# ── 3. Ký ─────────────────────────────────────────────────────────────────
# Quyền Accessibility gắn với chữ ký của app. Ký bằng một chứng chỉ cố định thì
# quyền đã cấp vẫn còn sau mỗi lần build lại; ký ad-hoc thì mỗi bản build là một
# danh tính mới nên phải cấp quyền lại.
say "3/4  Ký"
# Chứng chỉ có thể bị THU HỒI bất cứ lúc nào. Khi đó macOS từ chối chạy app
# (lỗi "Launch failed" 163), tự XOÁ bundle khỏi /Applications, và thu hồi luôn
# quyền Accessibility đã cấp. Nên phải thử ký rồi kiểm tra thật, chứ không
# được tin vào việc chứng chỉ có mặt trong Keychain.
sign_and_check() {
  local ident="$1"
  codesign --force --options runtime --sign "$ident" "$APP" >/dev/null 2>&1 \
    || codesign --force --sign "$ident" "$APP" >/dev/null 2>&1 \
    || return 1
  spctl -a -vv "$APP" 2>&1 | grep -q "REVOKED" && return 2
  return 0
}

IDENTITY=""
if [ "$ADHOC" -eq 0 ]; then
  CANDIDATES=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E "Developer ID Application|Apple Development" | sed -E 's/.*"(.*)"/\1/')
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    sign_and_check "$cand"
    case $? in
      0) IDENTITY="$cand"; break ;;
      2) warn "bỏ qua (chứng chỉ bị thu hồi): $cand" ;;
      *) warn "bỏ qua (ký thất bại): $cand" ;;
    esac
  done <<< "$CANDIDATES"
fi

if [ -n "$IDENTITY" ]; then
  ok "đã ký: $IDENTITY"
  ok "quyền Accessibility sẽ được giữ qua các lần build lại"
else
  codesign --force --sign - "$APP" || die "ký ad-hoc thất bại"
  spctl -a -vv "$APP" 2>&1 | grep -q "REVOKED" && die "ngay cả chữ ký ad-hoc cũng bị từ chối"
  ok "ký ad-hoc"
  warn "mỗi lần build lại là một danh tính mới → phải cấp lại quyền Accessibility"
fi
codesign --verify --strict "$APP" >/dev/null 2>&1 && ok "chữ ký hợp lệ" || warn "chữ ký không xác minh được"

# Làm mới bản dùng ngay trong auto/ — chỗ để bấm đúp cài, không cần Xcode
mkdir -p auto
rm -rf "auto/$NAME.app"
cp -R "$APP" "auto/$NAME.app"
ok "auto/$NAME.app (bản dùng cho \"Cài đặt.command\")"

# ── 4. Cài đặt ────────────────────────────────────────────────────────────
say "4/4  Xong"
if [ "$INSTALL" -eq 1 ]; then
  osascript -e "tell application \"$NAME\" to quit" >/dev/null 2>&1
  pkill -x "$NAME" >/dev/null 2>&1
  sleep 1
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/ || die "không chép được vào /Applications"
  ok "đã cài /Applications/$NAME.app"
  open "/Applications/$NAME.app"
  ok "đã mở"
else
  ok "$(pwd)/$APP"
  echo
  echo "  Cài: vào auto/ bấm đúp \"Cài đặt.command\", hoặc chạy lại với --install"
fi

cat <<'EOF'

  Lần đầu chạy sẽ hỏi quyền Accessibility. Bật công tắc cho SafariMRUTabs
  trong System Settings > Privacy & Security > Accessibility — app tự khởi
  động lại ngay khi thấy quyền đã được cấp.

  Phím tắt:
    Control + Tab          quay lại tab dùng gần nhất
    Control + Shift + Tab  lùi sâu hơn trong lịch sử
    Control + Option + T   bật / tắt

EOF
