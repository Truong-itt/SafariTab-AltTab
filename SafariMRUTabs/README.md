# Safari MRU Tabs — bản app gốc (Swift)

Đổi `Control + Tab` trong Safari thành "quay lại tab dùng gần nhất" (MRU).
Không cần Hammerspoon, không cần Homebrew — một app độc lập ~2 MB.

App **chạy hoàn toàn ẩn**: không icon dock, không icon thanh menu, không cửa
sổ. Cài xong là chạy và tự khởi động cùng macOS.

---

## Cài

Cần Xcode hoặc Command Line Tools (`xcode-select --install`) — app đã build
không nằm trong git nên lần đầu phải build từ mã nguồn. Chọn một trong hai:

- **Bằng Terminal:** `bash build.sh --install`
- **Bấm đúp:** vào thư mục [auto/](auto/) → bấm đúp **`Cài đặt.command`**.
  Chưa có bản build sẵn thì nó tự gọi `build.sh` trước.

Cả hai cách đều chép app vào `/Applications` và chạy nó. Lần đầu cài sẽ phải
bật công tắc cho **SafariMRUTabs** trong
`System Settings` → `Privacy & Security` → `Accessibility`; app tự khởi động
lại ngay khi thấy quyền đã được cấp.

> Nếu macOS chặn vì file tải từ mạng: chuột phải vào `Cài đặt.command` →
> `Open` → `Open` lần nữa.

## Gỡ

Bấm đúp **`auto/Gỡ cài đặt.command`** — dừng app, huỷ đăng ký khởi động cùng
macOS, xoá app và xoá tuỳ chọn.

---

## Phím tắt

| Phím | Tác dụng |
|---|---|
| `Control + Tab` | Quay lại tab dùng gần nhất; bấm lại → quay về chỗ cũ |
| `Control + Shift + Tab` | Lùi sâu hơn: bấm liên tiếp trong 1.2 giây thì mỗi lần lùi thêm một bậc |
| `Control + Option + T` | Bật / tắt, có thông báo ngắn giữa màn hình |

Phím chỉ hoạt động khi Safari đang là app phía trước. Khi tắt bằng `⌃⌥T`,
`Control + Tab` trở về hành vi mặc định của Safari ngay lập tức.

---

## Không có icon thì điều khiển bằng gì

Đây là đánh đổi có chủ ý: app ẩn hoàn toàn nên mọi thứ chuyển sang phím tắt,
`defaults`, và log.

| Việc | Cách làm |
|---|---|
| Bật / tắt | `Control + Option + T` |
| Dừng hẳn | `pkill -x SafariMRUTabs`, hoặc `Gỡ cài đặt.command` |
| Chạy lại | `open -a SafariMRUTabs` |
| Xem chẩn đoán | lệnh `log show` bên dưới |
| Chỉ chuyển trong cửa sổ hiện tại | `defaults write com.hihi.SafariMRUTabs sameWindowOnly -bool true` rồi khởi động lại app |
| Trả về mặc định | `defaults delete com.hihi.SafariMRUTabs sameWindowOnly` |

Chẩn đoán (app ghi một bản đầy đủ mỗi lần khởi động):

```bash
log show --last 10m --predicate 'subsystem == "com.hihi.SafariMRUTabs"' --style compact
```

Bản chẩn đoán cho biết: quyền Accessibility, đang bật hay tắt, Safari có ở phía
trước không, phím tắt có đang bắt không, thanh tab đọc được mấy tab, và lịch sử
MRU hiện tại.

---

## Build lại từ mã nguồn

```bash
bash build.sh            # build + ký, xuất ra auto/SafariMRUTabs.app
bash build.sh --install  # build xong chép luôn vào /Applications và mở
bash build.sh --adhoc    # ký ad-hoc, dùng khi build để gửi máy khác
```

Cần Xcode hoặc Command Line Tools (`xcode-select --install`). Build ra universal
binary (Apple Silicon + Intel), macOS 13 trở lên.

**Về chữ ký:** quyền Accessibility gắn với chữ ký của app. `build.sh` ưu tiên
ký bằng chứng chỉ `Apple Development` có sẵn trong Keychain, nhờ vậy quyền đã
cấp vẫn còn sau mỗi lần build lại. Ký ad-hoc (`--adhoc`) thì mỗi bản build là
một danh tính mới nên phải cấp lại quyền.

---

## Bẫy: chứng chỉ ký bị thu hồi

Đây là sự cố đã thực sự xảy ra, mất 5 ngày mới lộ ra, nên ghi lại cho rõ.

Nếu chứng chỉ dùng để ký app bị Apple thu hồi thì:

- macOS **từ chối chạy** app: `Launch failed`, `NSPOSIXErrorDomain Code=163`
- macOS **tự xoá** bundle khỏi `/Applications` ngay sau khi bạn chép vào —
  trông như file "tự biến mất"
- Quyền Accessibility đã cấp **bị thu hồi theo**, vì quyền gắn với danh tính ký
- Tiến trình đang chạy thì **không bị giết**, nên app trông như vẫn hoạt động:
  phần dò "Safari ở phía trước" dùng NSWorkspace (không cần quyền) vẫn chạy
  bình thường, chỉ có các lệnh đọc tab là trả rỗng

Kiểm tra:

```bash
spctl -a -vv /Applications/SafariMRUTabs.app
```

Thấy `CSSMERR_TP_CERT_REVOKED` là dính. Cách chữa: `bash build.sh` — script tự
thử từng chứng chỉ, bỏ qua cái bị thu hồi, và rơi về ad-hoc nếu không còn cái
nào dùng được. Sau khi đổi chứng chỉ thì **phải cấp lại quyền Accessibility**
(xoá mục cũ bằng `−` rồi thêm lại bằng `+`), vì Team ID đã khác.

App cũng tự canh: mất quyền giữa chừng sẽ hiện thông báo trên màn hình thay vì
im lặng hỏng.

---

## Gửi cho người khác

Chạy `bash build.sh --adhoc` rồi nén thư mục `auto/` (lúc này đã có
`SafariMRUTabs.app` bên trong) và gửi — máy nhận không cần Xcode. Máy nhận sẽ gặp Gatekeeper vì app chưa được
notarize: chuột phải vào app → `Open` → `Open`, hoặc vào
`System Settings` → `Privacy & Security` → `Open Anyway`.

Muốn không còn cảnh báo thì phải notarize qua tài khoản Apple Developer
(99 USD/năm) — chứng chỉ `Apple Development` đang dùng không đủ.

---

## Cấu trúc mã nguồn

| File | Vai trò |
|---|---|
| `Sources/main.swift` | Điểm vào, dựng NSApplication |
| `Sources/AppDelegate.swift` | Vòng đời, quyền Accessibility, phím bật/tắt, đăng ký khởi động cùng macOS |
| `Sources/MRUController.swift` | Lịch sử MRU, theo dõi tab, logic chuyển tab |
| `Sources/SafariTabs.swift` | Đọc thanh tab Safari qua Accessibility |
| `Sources/HotkeyManager.swift` | Đăng ký phím tắt toàn cục (Carbon `RegisterEventHotKey`) |
| `Sources/AX.swift` | Bọc Accessibility API cho gọn |
| `Sources/HUD.swift` | Thông báo ngắn giữa màn hình |
| `Sources/Log.swift` | Ghi log qua `os.Logger` |
| `Resources/Info.plist` | `LSUIElement` = true (app ẩn) |

Ghi chú kỹ thuật quan trọng về cấu trúc Accessibility của Safari 26 nằm ở
[../README.md](../README.md#7-ghi-chú-kỹ-thuật).
