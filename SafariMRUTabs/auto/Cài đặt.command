#!/bin/bash
# Bấm đúp file này để cài Safari MRU Tabs.
# Không cần Xcode, không cần Terminal — chỉ chép app đã build sẵn vào Applications.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

NAME="SafariMRUTabs"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

printf '\n\033[1mCài đặt Safari MRU Tabs\033[0m\n\n'

# ── Tìm app đã build sẵn ──────────────────────────────────────────────────
SRC=""
for candidate in "./$NAME.app" "../$NAME.app" "../build/$NAME.app" "./build/$NAME.app"; do
  [ -d "$candidate" ] && { SRC="$candidate"; break; }
done

if [ -z "$SRC" ]; then
  warn "chưa có bản build sẵn"
  if command -v swiftc >/dev/null 2>&1; then
    echo "  Đang build từ mã nguồn…"
    BUILDER=""
    for b in "./build.sh" "../build.sh"; do [ -f "$b" ] && { BUILDER="$b"; break; }; done
    [ -n "$BUILDER" ] && bash "$BUILDER" >/dev/null 2>&1
    for candidate in "../$NAME.app" "../build/$NAME.app" "./build/$NAME.app"; do
      [ -d "$candidate" ] && { SRC="$candidate"; break; }
    done
  fi
  [ -n "$SRC" ] && [ -d "$SRC" ] || {
    fail "không tìm thấy $NAME.app và cũng không build được"
    fail "cần Xcode để build: xcode-select --install"
    echo; read -r -p "  Bấm Enter để đóng… " _; exit 1
  }
fi
ok "nguồn: $SRC"

# ── Thoát bản đang chạy ───────────────────────────────────────────────────
osascript -e "tell application \"$NAME\" to quit" >/dev/null 2>&1
pkill -x "$NAME" >/dev/null 2>&1
sleep 1

# ── Chép vào Applications ─────────────────────────────────────────────────
rm -rf "/Applications/$NAME.app"
if ! cp -R "$SRC" "/Applications/$NAME.app"; then
  fail "không chép được vào /Applications"
  echo; read -r -p "  Bấm Enter để đóng… " _; exit 1
fi
xattr -dr com.apple.quarantine "/Applications/$NAME.app" 2>/dev/null
ok "đã cài /Applications/$NAME.app"

# ── Chạy ──────────────────────────────────────────────────────────────────
open "/Applications/$NAME.app"
sleep 3
ok "đã mở — chạy ẩn, không có icon dock hay thanh menu"

# ── Kiểm tra quyền Accessibility qua log của chính app ────────────────────
echo
STATE=$(/usr/bin/log show --last 1m \
  --predicate 'subsystem == "com.hihi.SafariMRUTabs"' --style compact 2>/dev/null \
  | grep -o "quyền Accessibility: .*" | tail -1)

case "$STATE" in
  *"đã cấp"*)
    ok "quyền Accessibility: đã cấp — dùng được ngay"
    ;;
  *"CHƯA cấp"*)
    warn "quyền Accessibility: CHƯA cấp"
    echo
    echo "  Đang mở System Settings. Bật công tắc cho $NAME trong danh sách."
    echo "  App tự khởi động lại ngay khi thấy quyền được cấp."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ;;
  *)
    warn "chưa đọc được trạng thái quyền"
    echo "  Xem chi tiết bằng lệnh:"
    echo "    log show --last 5m --predicate 'subsystem == \"com.hihi.SafariMRUTabs\"' --style compact"
    ;;
esac

cat <<'EOF'

  App chạy ẩn hoàn toàn và tự khởi động cùng macOS. Không có icon để bấm —
  điều khiển bằng phím tắt:

    Control + Tab          quay lại tab dùng gần nhất
    Control + Shift + Tab  lùi sâu hơn trong lịch sử
    Control + Option + T   bật / tắt (hiện thông báo giữa màn hình)

  Muốn dừng hẳn hoặc gỡ: bấm đúp "Gỡ cài đặt.command" cạnh file này.

EOF
read -r -p "  Bấm Enter để đóng cửa sổ này… " _
