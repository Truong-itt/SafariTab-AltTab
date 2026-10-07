-- ~/.hammerspoon/init.lua
-- Cấu hình Hammerspoon: bật công cụ chuyển tab Safari theo kiểu MRU.

-- Cho phép điều khiển từ Terminal bằng lệnh `hs` (dùng để kiểm tra/chẩn đoán)
pcall(require, "hs.ipc")

local mru = require("safari_mru_tabs")

-- ─────────────────────────────────────────────────────────────────────────
-- Tuỳ chỉnh (bỏ dấu -- ở đầu dòng để dùng)
-- ─────────────────────────────────────────────────────────────────────────
-- mru.config.debug           = true      -- in log ra Console để chẩn đoán
-- mru.config.captureMethod   = "eventtap"-- dùng nếu Ctrl+Tab không bị chặn được
-- mru.config.sameWindowOnly  = true      -- chỉ chuyển trong cửa sổ đang mở
-- mru.config.enableDeepCycle = false     -- trả Ctrl+Shift+Tab về mặc định Safari
-- mru.config.pollInterval    = 0.6       -- tăng lên nếu muốn nhẹ hơn nữa
-- mru.config.switchMethod    = "applescript" -- ép dùng AppleScript thay vì AXPress

mru.start()

-- Cho phép gọi từ Hammerspoon Console: safariMRU.dump() / safariMRU.probe()
safariMRU = mru

-- ─────────────────────────────────────────────────────────────────────────
-- Tự nạp lại cấu hình khi file .lua thay đổi
-- ─────────────────────────────────────────────────────────────────────────
hs.configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(paths)
  for _, p in ipairs(paths) do
    if p:sub(-4) == ".lua" then
      hs.reload()
      return
    end
  end
end):start()

hs.alert.show("Hammerspoon: Safari MRU Tab đã sẵn sàng", 1.2)
