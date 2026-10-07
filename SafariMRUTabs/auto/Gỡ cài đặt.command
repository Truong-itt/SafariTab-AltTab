#!/bin/bash
# Bấm đúp file này để gỡ Safari MRU Tabs.
# App không có icon thanh menu nên đây là cách dừng và xoá nó.

NAME="SafariMRUTabs"
APP="/Applications/$NAME.app"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

printf '\n\033[1mGỡ Safari MRU Tabs\033[0m\n\n'

# Huỷ đăng ký khởi động cùng macOS trước khi xoá, tránh để lại mục rác
# trong System Settings > General > Login Items.
if [ -x "$APP/Contents/MacOS/$NAME" ]; then
  "$APP/Contents/MacOS/$NAME" --uninstall >/dev/null 2>&1 &
  sleep 2
  ok "đã huỷ khởi động cùng macOS"
fi

pkill -x "$NAME" >/dev/null 2>&1
sleep 1
pgrep -x "$NAME" >/dev/null && pkill -9 -x "$NAME" >/dev/null 2>&1
pgrep -x "$NAME" >/dev/null && warn "vẫn còn tiến trình chạy" || ok "đã dừng"

if [ -d "$APP" ]; then
  rm -rf "$APP" && ok "đã xoá $APP" || warn "không xoá được $APP"
else
  warn "không thấy $APP (có thể đã gỡ rồi)"
fi

defaults delete com.hihi.SafariMRUTabs >/dev/null 2>&1 && ok "đã xoá tuỳ chọn" || true

cat <<'EOF'

  Xong. Control+Tab trong Safari trở về hành vi mặc định.

  Nếu System Settings > General > Login Items còn sót mục SafariMRUTabs,
  chọn nó rồi bấm "−" để xoá.

EOF
read -r -p "  Bấm Enter để đóng cửa sổ này… " _
