# Safari MRU Tab Switcher

Đổi `Control + Tab` trong Safari thành "quay lại tab dùng gần nhất" (MRU —
Most Recently Used), thay vì nhảy sang tab bên phải. Giống cách `Command + Tab`
nhảy qua lại giữa hai ứng dụng gần nhất.

Ví dụ: đang ở A → sang B → sang C. Bấm `Ctrl+Tab` → về B. Bấm nữa → về C.

| Phím | Tác dụng |
|---|---|
| `Control + Tab` | Quay lại tab dùng gần nhất (bấm lại → quay về chỗ cũ) |
| `Control + Shift + Tab` | Lùi sâu hơn trong lịch sử (bấm liên tiếp trong 1.2 giây) |
| `Control + Option + T` | Bật / tắt công cụ |

Phím tắt chỉ hoạt động khi Safari đang là ứng dụng phía trước.

---

## Hai phiên bản — chọn một

Kho này chứa hai bản cài đặt độc lập của cùng một tính năng. **Chỉ cài một
bản**, vì cả hai cùng giành phím `Control + Tab`.

| | App gốc (Swift) | Hammerspoon (Lua) |
|---|---|---|
| Thư mục | [SafariMRUTabs/](SafariMRUTabs/) | thư mục gốc của kho |
| Cần cài thêm | Xcode Command Line Tools (để build) | Homebrew + Hammerspoon |
| Giao diện | Chạy ẩn hoàn toàn, không icon | Icon Hammerspoon trên thanh menu |
| Tuỳ chỉnh | Ít (qua `defaults`) | Nhiều (sửa `init.lua`, tự nạp lại) |
| Hợp với | Người chỉ muốn cài xong là quên | Người đã dùng Hammerspoon hoặc muốn sửa code |
| Hướng dẫn | [SafariMRUTabs/README.md](SafariMRUTabs/README.md) | các mục 1–8 bên dưới |

Yêu cầu chung: macOS 13 trở lên, Safari, và quyền **Accessibility**.

## Bắt đầu nhanh

```bash
git clone https://github.com/Truong-itt/controltabsafari.git
cd controltabsafari
```

**Bản app gốc (Swift):**

```bash
xcode-select --install                    # bỏ qua nếu đã có Xcode / Command Line Tools
bash SafariMRUTabs/build.sh --install     # build, ký, chép vào /Applications và mở
```

**Bản Hammerspoon:**

```bash
bash install.sh
```

Cả hai bản đều dừng ở một bước phải làm tay: bật công tắc cho app
(`SafariMRUTabs` hoặc `Hammerspoon`) trong `System Settings` →
`Privacy & Security` → `Accessibility`.

Kiểm tra: mở Safari với từ 2 tab trở lên, đổi qua lại vài tab, rồi bấm
`Control + Tab` — phải quay về tab vừa dùng, không trượt sang phải.

## Cấu trúc kho

```
.
├── README.md              ← file này (tổng quan + hướng dẫn bản Hammerspoon)
├── install.sh             ← trình cài bản Hammerspoon
├── init.lua               ← cấu hình Hammerspoon, nạp module
├── safari_mru_tabs.lua    ← toàn bộ logic bản Hammerspoon
└── SafariMRUTabs/         ← bản app gốc (Swift)
    ├── README.md
    ├── build.sh           ← build + ký + (tuỳ chọn) cài
    ├── Sources/           ← mã nguồn Swift
    ├── Resources/Info.plist
    └── auto/              ← "Cài đặt.command" / "Gỡ cài đặt.command" (bấm đúp)
```

App đã build (`SafariMRUTabs.app`) **không nằm trong git** — chữ ký của nó gắn
với Apple ID của người build. Mỗi máy tự build bằng `build.sh`.

---

# Bản Hammerspoon

## 1. Cài đặt

Giữ nguyên thư mục này ở đâu đó an toàn (kho git, iCloud Drive, ổ backup…) —
nó là toàn bộ thứ cần để cài lại. Sau đó:

```bash
cd <thư-mục-này>
bash install.sh
```

Script tự làm hết: cài Hammerspoon qua Homebrew nếu chưa có, chép file cấu
hình, khởi động lại Hammerspoon, kiểm tra quyền Accessibility (mở sẵn System
Settings và chờ nếu chưa có), bật tự khởi động cùng macOS, rồi xác nhận module
đã nạp. Chạy lại nhiều lần vô hại — nó tự nhận biết cái gì đã có.

Bước duy nhất phải làm tay là **bật công tắc Hammerspoon** trong
`System Settings` → `Privacy & Security` → `Accessibility`. Script sẽ dừng chờ
ở đúng chỗ đó.

### Ba chỗ dễ vấp

- **Cấp quyền xong vẫn không chạy** → phải **thoát hẳn** Hammerspoon rồi mở
  lại; `Reload Config` không đủ, tiến trình chỉ nhận quyền mới lúc khởi động.
  Script đã tự làm việc này.
- **Cài lại trên máy cũ**: macOS thường còn lưu mục Hammerspoon trong danh sách
  Accessibility nhưng trỏ vào bản cũ đã bị xoá. Chọn nó → bấm `−` xoá đi →
  bấm `+` thêm lại `/Applications/Hammerspoon.app`.
- **Đã có `~/.hammerspoon/init.lua` riêng** → script sao lưu thành
  `init.lua.backup.<ngày-giờ>` chứ không ghép giúp. Ghép tay bằng cách thêm vào
  file của bạn:

  ```lua
  local mru = require("safari_mru_tabs")
  mru.start()
  ```

### Cài tay (nếu không muốn dùng script)

```bash
brew install --cask hammerspoon
mkdir -p ~/.hammerspoon
cp safari_mru_tabs.lua init.lua ~/.hammerspoon/
open -a Hammerspoon
# cấp quyền Accessibility, rồi thoát hẳn Hammerspoon và mở lại
```

Bật tự khởi động: menu bar Hammerspoon → `Preferences` → tích
**Launch Hammerspoon at login**.

> Quyền **Automation** cho Safari chỉ cần khi nhánh dự phòng AppleScript được
> dùng; macOS sẽ tự hỏi lúc đó. Đường chính (Accessibility) không cần.

---

## 2. Các file

| File | Vị trí sau khi cài | Vai trò |
|---|---|---|
| `safari_mru_tabs.lua` | `~/.hammerspoon/safari_mru_tabs.lua` | Toàn bộ logic: theo dõi tab, lưu lịch sử, chuyển tab, hotkey |
| `init.lua` | `~/.hammerspoon/init.lua` | Cấu hình Hammerspoon, nạp module, auto-reload |
| `install.sh` | (chỉ dùng để cài) | Trình cài đặt: Hammerspoon, chép file, quyền, tự khởi động |

## 3. Phím tắt

| Phím | Tác dụng |
|---|---|
| `Ctrl + Tab` | Quay lại tab dùng gần nhất (bấm lại → quay về chỗ cũ) |
| `Ctrl + Shift + Tab` | Lùi sâu trong lịch sử: bấm 1 lần → tab gần nhất, bấm liên tiếp trong 1.2 giây → lùi tiếp 1 bậc mỗi lần, ngừng bấm thì chốt |
| `Ctrl + Option + T` | Bật / tắt công cụ (hiện thông báo ngắn) |

Khi tắt, `Ctrl+Tab` trả về hành vi mặc định của Safari ngay lập tức.
Phím tắt chỉ hoạt động khi Safari là ứng dụng đang hoạt động — các app khác
không bị ảnh hưởng.

---

## 4. Kiểm tra khi có sự cố

Mở **Hammerspoon Console** (menu bar → Console), gõ:

```lua
safariMRU.probe()    -- Safari có lộ thanh tab qua Accessibility không?
safariMRU.dump()     -- xem lịch sử tab đang lưu
safariMRU.status()   -- trạng thái nội bộ: front, hotkeysActive, observer, poller
```

`status()` là chỗ nhìn đầu tiên khi phím tắt không ăn. Khi Safari đang ở phía
trước, phải thấy `safariFrontmost = true` và `hotkeysActive = true`.

`probe()` phải in ra danh sách tab và tab đang chọn, ví dụ:

```
Thanh tab: role=AXOpaqueProviderGroup subrole=AXOpaqueProviderList — 12 tab
   1. asIdx=1   value=true  Google Drive
   2. asIdx=2   value=false Google Dịch
   ...
```

Nếu in `KHÔNG tìm thấy thanh tab`:

- Cửa sổ chỉ có 1 tab (bình thường — không có gì để chuyển)
- Thanh tab đang ẩn: Safari → `View` → `Show Tab Bar`
- Hoặc Safari đã đổi cấu trúc Accessibility ở bản mới

Bật log chi tiết: sửa `~/.hammerspoon/init.lua`, bỏ comment dòng
`mru.config.debug = true`, lưu file (tự reload).

---

## 5. Nếu `Ctrl + Tab` không bị chặn được

Thử lần lượt:

**Cách A — đổi sang eventtap** (bắt phím ở tầng thấp hơn). Trong `init.lua`:

```lua
mru.config.captureMethod = "eventtap"
```

**Cách B — vô hiệu hoá phím mặc định của Safari.** `System Settings` →
`Keyboard` → `Keyboard Shortcuts…` → `App Shortcuts` → `+`:

- Application: `Safari`
- Menu Title: `Show Next Tab` (đúng y hệt tên trong menu `Window` của Safari)
- Keyboard Shortcut: gán một phím lạ, ví dụ `⌃⌥⌘9`

Làm tương tự với `Show Previous Tab`. Sau đó `Ctrl+Tab` không còn ý nghĩa với
Safari và Hammerspoon giữ trọn phím.

**Cách C — dùng phím thay thế.** Trong `init.lua`:

```lua
mru.config.switchMods = { "ctrl", "alt" }
mru.config.switchKey  = "tab"      -- hoặc "`", "j", ...
```

---

## 6. Tuỳ chọn cấu hình

Đặt trong `init.lua` **trước** `mru.start()`:

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `captureMethod` | `"hotkey"` | `"hotkey"` hoặc `"eventtap"` |
| `sameWindowOnly` | `false` | `true` = không nhảy sang cửa sổ Safari khác |
| `enableDeepCycle` | `true` | `false` = trả `Ctrl+Shift+Tab` về mặc định |
| `pollInterval` | `0.4` | Chu kỳ quét dự phòng (giây), chỉ chạy khi Safari ở phía trước |
| `maxHistory` | `50` | Số mục lịch sử tối đa |
| `switchMethod` | `"auto"` | `"ax"` / `"applescript"` để ép một cách chuyển |
| `showAlerts` | `true` | Thông báo khi bật/tắt |
| `debug` | `false` | In log ra Console |

---

## 7. Ghi chú kỹ thuật

Cấu trúc Accessibility của thanh tab **đã đổi ở Safari 26**: thanh tab là con
trực tiếp của `AXWindow` với subrole `AXOpaqueProviderList` (Safari cũ đặt nó
trong `AXTabGroup`). Code dò cả hai: ưu tiên subrole đó, nếu không có thì tìm
phần tử đầu tiên có con là `AXRadioButton`.

Mỗi tab được nhận dạng bằng chính `AXUIElement` của nó — `AXIdentifier` của
Safari giống hệt nhau giữa các tab nên không dùng được, còn chỉ số thì đổi khi
đóng/kéo tab.

Hai điểm đáng lưu ý nếu bạn tự sửa code:

- `hs.application.watcher` **không** phát sự kiện `activated` nếu Safari đã sẵn
  ở phía trước lúc cấu hình được nạp. Vì vậy có thêm một timer 1 giây đồng bộ
  lại trạng thái — thiếu nó, phím tắt có thể không bao giờ được bật.
- Hotkey kiểu Carbon **không phản ứng với sự kiện phím do phần mềm tạo ra**
  (`hs.eventtap.keyStroke`). Muốn kiểm tra `Ctrl+Tab` thì phải bấm phím thật.

---

## 8. Gỡ cài đặt

```bash
rm ~/.hammerspoon/safari_mru_tabs.lua
rm ~/.hammerspoon/init.lua        # hoặc khôi phục từ file .backup.*
```

Rồi Reload Config, hoặc thoát Hammerspoon.
