#!/bin/bash
# Cài đặt Safari MRU Tab Switcher.
# Chạy lại bao nhiêu lần cũng được — script tự nhận biết cái gì đã có.
#
#   bash install.sh

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.hammerspoon"
APP="/Applications/Hammerspoon.app"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }

# Tìm CLI `hs` (Apple Silicon / Intel / PATH)
find_hs() {
  for p in "$(command -v hs 2>/dev/null)" /opt/homebrew/bin/hs /usr/local/bin/hs; do
    [ -n "$p" ] && [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

# Chạy lệnh Lua trong Hammerspoon, thử lại tối đa 15 giây
hs_eval() {
  local hs; hs=$(find_hs) || return 1
  local i=0
  while [ $i -lt 15 ]; do
    local out; out=$("$hs" -c "$1" 2>/dev/null | tail -1)
    if [ -n "$out" ] && [ "$out" != "nil" ]; then echo "$out"; return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}

# ── 1. Hammerspoon ────────────────────────────────────────────────────────
say "1/5  Hammerspoon"
if [ -d "$APP" ]; then
  ok "đã có $APP"
else
  command -v brew >/dev/null || die "chưa có Homebrew. Cài tại https://brew.sh rồi chạy lại."
  warn "chưa cài — đang cài qua Homebrew…"
  brew install --cask hammerspoon || die "cài Hammerspoon thất bại"
  ok "đã cài Hammerspoon"
fi

# ── 2. Chép file cấu hình ─────────────────────────────────────────────────
say "2/5  File cấu hình"
mkdir -p "$DEST"
for f in safari_mru_tabs.lua init.lua; do
  [ -f "$SRC/$f" ] || die "thiếu file nguồn: $SRC/$f"
done
if [ -f "$DEST/init.lua" ] && ! cmp -s "$SRC/init.lua" "$DEST/init.lua"; then
  BACKUP="$DEST/init.lua.backup.$(date +%Y%m%d-%H%M%S)"
  cp "$DEST/init.lua" "$BACKUP"
  warn "init.lua cũ khác nội dung — đã sao lưu: $BACKUP"
  warn "nếu bạn có cấu hình Hammerspoon riêng, hãy ghép tay từ file đó"
fi
cp "$SRC/safari_mru_tabs.lua" "$DEST/safari_mru_tabs.lua"
cp "$SRC/init.lua"            "$DEST/init.lua"
ok "$DEST/safari_mru_tabs.lua"
ok "$DEST/init.lua"

# ── 3. Khởi động lại Hammerspoon ──────────────────────────────────────────
# Thoát hẳn chứ không chỉ Reload Config: quyền Accessibility vừa cấp chỉ được
# nhận sau khi tiến trình khởi động lại.
say "3/5  Khởi động lại Hammerspoon"
osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1
sleep 2
pkill -x Hammerspoon >/dev/null 2>&1
sleep 1
open -a Hammerspoon || die "không mở được Hammerspoon"
sleep 4
pgrep -x Hammerspoon >/dev/null && ok "đang chạy (pid $(pgrep -x Hammerspoon))" || die "Hammerspoon không chạy"

# ── 4. Quyền Accessibility ────────────────────────────────────────────────
say "4/5  Quyền Accessibility"
if ! find_hs >/dev/null; then
  warn "chưa thấy CLI 'hs' — bỏ qua bước kiểm tra tự động"
  warn "hãy tự cấp quyền trong System Settings > Privacy & Security > Accessibility"
else
  STATE=$(hs_eval 'return tostring(hs.accessibilityState())' || echo "unknown")
  if [ "$STATE" = "true" ]; then
    ok "đã được cấp"
  else
    warn "CHƯA được cấp — đang mở System Settings…"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    hs_eval 'hs.accessibilityState(true) return "prompted"' >/dev/null 2>&1
    echo
    echo "  Bật công tắc cho Hammerspoon trong danh sách Accessibility."
    echo "  (Nếu Hammerspoon đã có sẵn trong danh sách mà vẫn không chạy:"
    echo "   chọn nó, bấm '−' để xoá, rồi bấm '+' thêm lại /Applications/Hammerspoon.app)"
    echo
    printf "  Bật xong thì bấm Enter để tiếp tục… "
    read -r _
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1
    sleep 2; pkill -x Hammerspoon >/dev/null 2>&1; sleep 1
    open -a Hammerspoon; sleep 4
    STATE=$(hs_eval 'return tostring(hs.accessibilityState())' || echo "unknown")
    [ "$STATE" = "true" ] && ok "đã được cấp" || warn "vẫn báo chưa được cấp ($STATE)"
  fi
fi

# ── 5. Tự khởi động + kiểm tra cuối ───────────────────────────────────────
say "5/5  Hoàn tất"
hs_eval 'hs.autoLaunch(true) return tostring(hs.autoLaunch())' >/dev/null 2>&1 \
  && ok "tự khởi động cùng macOS: bật" \
  || warn "không đặt được tự khởi động — bật tay trong Hammerspoon > Preferences"

STATUS=$(hs_eval 'local s = safariMRU.status() return string.format("enabled=%s running=%s capture=%s", tostring(s.enabled), tostring(s.running), s.captureMethod)' || echo "")
if [ -n "$STATUS" ]; then
  ok "module đã nạp — $STATUS"
else
  warn "chưa xác nhận được module. Mở Hammerspoon Console xem lỗi."
fi

cat <<'EOF'

  Kiểm tra: mở Safari (từ 2 tab trở lên), đổi qua lại vài tab,
  rồi bấm Control + Tab — phải quay về tab vừa dùng, không trượt sang phải.

  Phím tắt:
    Control + Tab          quay lại tab dùng gần nhất
    Control + Shift + Tab  lùi sâu hơn trong lịch sử
    Control + Option + T   bật / tắt công cụ

  Nếu Control+Tab không ăn, mở Hammerspoon Console và gõ:
    safariMRU.status()
  Khi Safari đang ở phía trước phải thấy safariFrontmost=true, hotkeysActive=true.
  Xem thêm mục 5 trong README.md.

EOF
