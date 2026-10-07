--- === safari_mru_tabs ===
---
--- Đổi hành vi Control+Tab trong Safari thành "chuyển tab theo thứ tự dùng gần
--- nhất" (MRU - Most Recently Used), giống cách Command+Tab nhảy qua lại giữa
--- hai ứng dụng gần nhất.
---
--- Cách hoạt động:
---   * Theo dõi tab đang hiển thị bằng Accessibility API (hs.axuielement),
---     kết hợp AXObserver (sự kiện) + một timer nhẹ (lưới an toàn).
---   * Mỗi tab được ghi nhớ bằng chính AXUIElement của nó, nên vẫn đúng khi
---     người dùng kéo đổi thứ tự tab, đóng tab, hoặc mở nhiều cửa sổ.
---   * Chuyển tab bằng AXPress lên phần tử tab; nếu thất bại thì rơi về
---     AppleScript (set current tab of window 1 to tab N).
---
--- Yêu cầu: Hammerspoon + quyền Accessibility (System Settings > Privacy &
--- Security > Accessibility). Chỉ cần quyền Automation cho Safari nếu nhánh
--- AppleScript dự phòng được dùng.

local ax          = require("hs.axuielement")
local application = require("hs.application")
local appwatcher  = require("hs.application.watcher")
local eventtap    = require("hs.eventtap")
local hotkey      = require("hs.hotkey")
local alert       = require("hs.alert")
local timer       = require("hs.timer")
local keycodes    = require("hs.keycodes")
local osascript   = require("hs.osascript")

local M = {}

---------------------------------------------------------------------------
-- Cấu hình (đổi trong init.lua trước khi gọi M.start())
---------------------------------------------------------------------------
M.config = {
  bundleID          = "com.apple.Safari",

  -- "hotkey"   : dùng hs.hotkey (Carbon RegisterEventHotKey) - nhẹ nhất, mặc định
  -- "eventtap" : dùng hs.eventtap - dự phòng nếu hotkey không cướp được phím
  captureMethod     = "hotkey",

  -- Phím chính: quay lại tab dùng gần nhất (bấm lần nữa thì quay lại chỗ cũ)
  switchMods        = { "ctrl" },
  switchKey         = "tab",

  -- Phím phụ: đi sâu hơn vào lịch sử (tab thứ 3, 4, ...) trong 1 "phiên duyệt"
  enableDeepCycle   = true,
  deepMods          = { "ctrl", "shift" },
  deepKey           = "tab",
  cycleTimeout      = 1.2,     -- giây; hết thời gian này thì chốt lựa chọn

  -- Phím bật/tắt toàn bộ công cụ (hoạt động ở mọi app)
  toggleMods        = { "ctrl", "alt" },
  toggleKey         = "t",

  pollInterval      = 0.4,     -- giây; chỉ chạy khi Safari đang là app phía trước
  maxHistory        = 50,      -- số mục lịch sử tối đa
  sameWindowOnly    = false,   -- true = chỉ chuyển trong cửa sổ đang focus
  switchMethod      = "auto",  -- "auto" | "ax" | "applescript"

  showAlerts        = true,    -- thông báo khi bật/tắt
  alertOnSwitchFail = true,    -- thông báo khi không có tab nào để quay lại
  debug             = false,
}

---------------------------------------------------------------------------
-- Trạng thái nội bộ
---------------------------------------------------------------------------
local S = {
  enabled     = true,
  running     = false,
  history     = {},      -- [1] = tab hiện tại, [2] = tab dùng gần nhất trước đó...
  hotkeys     = {},      -- hotkey chỉ bật khi Safari ở phía trước
  toggleHotkey= nil,     -- hotkey bật/tắt, luôn bật
  tap         = nil,
  observer    = nil,
  observerPid = nil,
  poller      = nil,
  appWatcher  = nil,
  watchedWins = {},
  barCache    = {},      -- cache thanh tab theo từng cửa sổ
  frontState  = nil,     -- Safari có đang ở phía trước không
  frontSync   = nil,
  hotkeysActive = nil,
  lastWinScan = 0,
  eqWorks     = nil,
  cycle       = { active = false, index = 1, entry = nil, timer = nil },
}

local function log(fmt, ...)
  if M.config.debug then
    print("[SafariMRU] " .. string.format(fmt, ...))
  end
end

---------------------------------------------------------------------------
-- Tiện ích Accessibility an toàn (không bao giờ ném lỗi ra ngoài)
---------------------------------------------------------------------------
local function attr(el, name)
  if el == nil then return nil end
  local ok, v = pcall(el.attributeValue, el, name)
  if ok then return v end
  return nil
end

local function isValid(el)
  if el == nil then return false end
  local ok, v = pcall(el.isValid, el)
  if ok and type(v) == "boolean" then return v end
  return attr(el, "AXRole") ~= nil
end

-- Một số bản Hammerspoon so sánh axuielement bằng "==" được, một số thì không.
-- Kiểm tra một lần lúc khởi động để chọn đường nhanh.
local function detectEquality()
  local ok, res = pcall(function()
    local a = ax.systemWideElement()
    local b = ax.systemWideElement()
    return a == b
  end)
  S.eqWorks = (ok and res == true)
  log("so sánh axuielement bằng '==': %s", tostring(S.eqWorks))
end

local function posKey(el)
  local p = attr(el, "AXPosition")
  if type(p) == "table" then
    return string.format("%d,%d", math.floor(tonumber(p.x) or 0), math.floor(tonumber(p.y) or 0))
  end
  return nil
end

--- So sánh hai phần tử AX có phải cùng một đối tượng hay không.
local function sameElement(a, b)
  if a == nil or b == nil then return false end
  local ok, res = pcall(function() return a == b end)
  if ok and res == true then return true end
  if S.eqWorks then return false end
  -- Dự phòng: cùng vai trò + cùng tiêu đề + cùng toạ độ
  local ra = attr(a, "AXRole")
  if ra == nil or ra ~= attr(b, "AXRole") then return false end
  if attr(a, "AXTitle") ~= attr(b, "AXTitle") then return false end
  local pa, pb = posKey(a), posKey(b)
  return pa ~= nil and pa == pb
end

---------------------------------------------------------------------------
-- Tìm thanh tab và danh sách tab
--
-- Safari 26 : thanh tab là con TRỰC TIẾP của AXWindow, subrole
--             AXOpaqueProviderList; mỗi tab là AXRadioButton (AXTabButton)
--             với AXValue kiểu boolean và AXIndex 0-based.
-- Safari cũ : thanh tab là AXTabGroup chứa các AXRadioButton.
-- Cả hai đều được phủ: tìm phần tử đầu tiên có con là AXRadioButton.
---------------------------------------------------------------------------
-- Không đi vào vùng nội dung web (rất nhiều phần tử, tốn CPU).
local SKIP_ROLES = {
  AXWebArea = true, AXScrollArea = true, AXTable = true, AXOutline = true,
  AXList = true, AXTextArea = true, AXTextField = true, AXImage = true,
  AXStaticText = true, AXMenuBar = true, AXMenu = true, AXSheet = true,
  AXBrowser = true, AXCell = true, AXRow = true, AXRadioButton = true,
}

local function isSelectedValue(v)
  return v == true or v == 1
end

local function findTabBar(win)
  if not isValid(win) then return nil end

  -- Đường nhanh cho Safari hiện tại
  local direct = attr(win, "AXChildren")
  if type(direct) == "table" then
    for _, c in ipairs(direct) do
      if attr(c, "AXSubrole") == "AXOpaqueProviderList" then return c end
    end
  end

  -- Đường tổng quát: phần tử đầu tiên có con là AXRadioButton
  local queue, head, visited = { { el = win, d = 0 } }, 1, 0
  while head <= #queue and visited < 400 do
    local node = queue[head]
    head = head + 1
    visited = visited + 1
    local role = attr(node.el, "AXRole")
    local kids = (not SKIP_ROLES[role or ""]) and attr(node.el, "AXChildren") or nil
    if type(kids) == "table" then
      for _, c in ipairs(kids) do
        if attr(c, "AXRole") == "AXRadioButton" then
          if node.d > 0 then return node.el end
          break
        end
      end
      if node.d < 8 then
        for _, c in ipairs(kids) do
          queue[#queue + 1] = { el = c, d = node.d + 1 }
        end
      end
    end
  end
  return nil
end

--- Cache thanh tab theo cửa sổ. Cache cả kết quả "không có thanh tab"
--- (cửa sổ 1 tab) trong 2 giây để khỏi quét cây liên tục.
local function tabBarFor(win)
  if win == nil then return nil end
  local now = timer.secondsSinceEpoch()
  for i = #S.barCache, 1, -1 do
    local c = S.barCache[i]
    if not isValid(c.win) then
      table.remove(S.barCache, i)
    elseif sameElement(c.win, win) then
      if c.bar ~= nil and isValid(c.bar) then return c.bar end
      if c.bar == nil and (now - c.t) < 2 then return nil end
      table.remove(S.barCache, i)
    end
  end
  local bar = findTabBar(win)
  S.barCache[#S.barCache + 1] = { win = win, bar = bar, t = now }
  while #S.barCache > 12 do table.remove(S.barCache, 1) end
  return bar
end

local function getTabs(bar)
  if not isValid(bar) then return {} end
  local t = attr(bar, "AXTabs")
  if type(t) == "table" and #t > 0 then return t end
  local out = {}
  local kids = attr(bar, "AXChildren")
  if type(kids) == "table" then
    for _, c in ipairs(kids) do
      if attr(c, "AXRole") == "AXRadioButton" then out[#out + 1] = c end
    end
  end
  return out
end

local function selectedTab(tabs, win)
  for i, t in ipairs(tabs) do
    if isSelectedValue(attr(t, "AXValue")) then return t, i end
  end
  -- Dự phòng: khớp tiêu đề cửa sổ với tiêu đề tab
  local wt = attr(win, "AXTitle")
  if wt ~= nil then
    for i, t in ipairs(tabs) do
      if attr(t, "AXTitle") == wt then return t, i end
    end
  end
  return nil, nil
end

--- Chỉ số dùng cho AppleScript (1-based). AXIndex của Safari là 0-based.
local function appleScriptIndex(tabEl, positionInList)
  local ix = attr(tabEl, "AXIndex")
  if type(ix) == "number" then return math.floor(ix) + 1 end
  return positionInList
end

---------------------------------------------------------------------------
-- Truy cập Safari
---------------------------------------------------------------------------
local function safariApp()
  return application.get(M.config.bundleID)
end

local function appElement()
  local app = safariApp()
  if app == nil then return nil end
  return ax.applicationElement(app)
end

local function focusedWindow()
  local ae = appElement()
  if ae == nil then return nil end
  local w = attr(ae, "AXFocusedWindow") or attr(ae, "AXMainWindow")
  if w == nil then
    local ws = attr(ae, "AXWindows")
    if type(ws) == "table" then w = ws[1] end
  end
  if w ~= nil and attr(w, "AXRole") ~= "AXWindow" then return nil end
  return w
end

local function isSafariFrontmost()
  local front = application.frontmostApplication()
  return front ~= nil and front:bundleID() == M.config.bundleID
end

---------------------------------------------------------------------------
-- Lịch sử tab
---------------------------------------------------------------------------
local function entryWindow(e)
  if e == nil then return nil end
  if e.tab ~= nil then
    local w = attr(e.tab, "AXWindow")   -- tab có thể đã bị kéo sang cửa sổ khác
    if w ~= nil then return w end
  end
  return e.win
end

local function entryAlive(e)
  if e == nil then return false end
  if e.tab ~= nil then
    if not isValid(e.tab) then return false end
    local w = attr(e.tab, "AXWindow")
    return w ~= nil and isValid(w)
  end
  return isValid(e.win)
end

local function sameEntry(a, b)
  if a == nil or b == nil then return false end
  if a.tab ~= nil and b.tab ~= nil then return sameElement(a.tab, b.tab) end
  if a.tab == nil and b.tab == nil then return sameElement(a.win, b.win) end
  return false
end

local function pushEntry(e)
  local h = S.history
  if sameEntry(h[1], e) then
    h[1].title = e.title or h[1].title
    h[1].index = e.index or h[1].index
    h[1].win   = e.win   or h[1].win
    return false
  end
  for i = #h, 1, -1 do
    if sameEntry(h[i], e) then table.remove(h, i) end
  end
  table.insert(h, 1, e)
  while #h > M.config.maxHistory do table.remove(h) end
  log("ghi nhận: %s (lịch sử = %d)", tostring(e.title), #h)
  return true
end

local function pruneHistory()
  for i = #S.history, 1, -1 do
    if not entryAlive(S.history[i]) then table.remove(S.history, i) end
  end
end

--- Đọc tab đang hiển thị và đẩy lên đầu lịch sử.
---
--- Đường nhanh: nếu mục đầu lịch sử vẫn là tab đang được chọn trong đúng cửa sổ
--- đang focus thì không có gì thay đổi — thoát chỉ sau 2-3 lần đọc thuộc tính.
--- Cách này không phụ thuộc tiêu đề nên vẫn đúng khi hai tab trùng tên.
local function recordCurrent(force)
  if not S.enabled then return end
  if S.cycle.active then return end          -- đang duyệt sâu: không xáo trộn lịch sử
  local win = focusedWindow()
  if win == nil then return end

  local cur = S.history[1]
  if not force and cur ~= nil and sameElement(cur.win, win) then
    if cur.tab ~= nil then
      if isSelectedValue(attr(cur.tab, "AXValue")) then return end
    elseif attr(win, "AXTitle") == cur.title then
      return                                  -- cửa sổ 1 tab, chưa đổi gì
    end
  end

  local tabEl, pos
  local bar = tabBarFor(win)
  if bar ~= nil then
    local tabs = getTabs(bar)
    if #tabs > 0 then tabEl, pos = selectedTab(tabs, win) end
  end

  pushEntry({
    win   = win,
    tab   = tabEl,                            -- nil = cửa sổ 1 tab, không có thanh tab
    index = (tabEl ~= nil) and appleScriptIndex(tabEl, pos) or nil,
    title = (tabEl ~= nil and attr(tabEl, "AXTitle")) or attr(win, "AXTitle"),
  })
end

---------------------------------------------------------------------------
-- Chuyển tab
---------------------------------------------------------------------------
local function applescriptSelect(idx)
  local script = string.format([[
tell application "Safari"
  if (count of windows) is 0 then return false
  set w to window 1
  if %d > (count of tabs of w) then return false
  set current tab of w to tab %d of w
  return true
end tell
]], idx, idx)
  local ok, result = osascript.applescript(script)
  return ok and result == true
end

--- Tìm lại phần tử tab của một mục lịch sử trong trạng thái hiện tại của Safari.
local function resolveTab(e)
  local win = entryWindow(e)
  if not isValid(win) then return nil, nil, nil end
  local bar = tabBarFor(win)
  local tabs = (bar ~= nil) and getTabs(bar) or {}

  if e.tab ~= nil then
    for i, t in ipairs(tabs) do
      if sameElement(t, e.tab) then return win, t, appleScriptIndex(t, i) end
    end
  end
  if e.title ~= nil then                       -- dự phòng: khớp theo tiêu đề
    for i, t in ipairs(tabs) do
      if attr(t, "AXTitle") == e.title then return win, t, appleScriptIndex(t, i) end
    end
  end
  if e.tab == nil and #tabs == 0 then
    return win, nil, nil                       -- cửa sổ 1 tab: chỉ cần đưa lên trước
  end
  return nil, nil, nil                         -- tab đã bị đóng
end

local function activateEntry(e)
  local win, tabEl, idx = resolveTab(e)
  if win == nil then return false end

  local app = safariApp()
  if app ~= nil then app:activate() end
  pcall(win.performAction, win, "AXRaise")
  pcall(win.setAttributeValue, win, "AXMain", true)

  if tabEl == nil then return true end

  local method = M.config.switchMethod
  if method ~= "applescript" then
    local ok, res = pcall(tabEl.performAction, tabEl, "AXPress")
    if ok and res ~= nil then
      e.win, e.tab, e.index = win, tabEl, idx
      return true
    end
    log("AXPress thất bại, thử AppleScript")
  end
  if method ~= "ax" and idx ~= nil and applescriptSelect(idx) then
    e.win, e.tab, e.index = win, tabEl, idx
    return true
  end
  return false
end

local function moveToFront(i)
  table.insert(S.history, 1, table.remove(S.history, i))
end

--- Danh sách chỉ số ứng viên, bắt đầu từ startAt.
local function candidateIndices(startAt)
  local frontWin = M.config.sameWindowOnly and focusedWindow() or nil
  local out = {}
  for i = startAt, #S.history do
    if frontWin == nil or sameElement(entryWindow(S.history[i]), frontWin) then
      out[#out + 1] = i
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Phiên "duyệt sâu" (Ctrl+Shift+Tab)
---------------------------------------------------------------------------
local function endCycle(commit)
  if S.cycle.timer ~= nil then
    S.cycle.timer:stop()
    S.cycle.timer = nil
  end
  if S.cycle.active and commit and S.cycle.entry ~= nil then
    for i = 1, #S.history do
      if S.history[i] == S.cycle.entry then moveToFront(i) break end
    end
  end
  S.cycle.active = false
  S.cycle.index  = 1
  S.cycle.entry  = nil
end

---------------------------------------------------------------------------
-- Hành động công khai
---------------------------------------------------------------------------
--- Quay lại tab dùng gần nhất. Bấm lần nữa sẽ quay về chỗ vừa rời đi.
function M.switchToPrevious()
  if not S.enabled then return end
  endCycle(true)
  recordCurrent(true)
  pruneHistory()

  for _, i in ipairs(candidateIndices(2)) do
    local e = S.history[i]
    if activateEntry(e) then
      moveToFront(i)
      log("chuyển sang: %s", tostring(e.title))
      return
    end
    log("mục đã chết, bỏ qua: %s", tostring(e.title))
  end

  if M.config.alertOnSwitchFail then
    alert.show("Safari MRU: chưa có tab nào để quay lại", 0.7)
  end
end

--- Đi sâu hơn vào lịch sử (tab thứ 3, 4, ...). Chốt sau `cycleTimeout` giây.
function M.cycleBack()
  if not S.enabled or not M.config.enableDeepCycle then return end

  if not S.cycle.active then
    recordCurrent(true)
    pruneHistory()
    S.cycle.active = true
    S.cycle.index  = 1
    S.cycle.entry  = nil
  end

  for _ = 1, #S.history + 1 do
    local list = candidateIndices(S.cycle.index + 1)
    if #list == 0 then list = candidateIndices(2) end   -- quay vòng về đầu
    local target = list[1]
    if target == nil then
      if M.config.alertOnSwitchFail then
        alert.show("Safari MRU: không có tab khác", 0.7)
      end
      endCycle(false)
      return
    end
    local e = S.history[target]
    if activateEntry(e) then
      S.cycle.index = target
      S.cycle.entry = e
      if S.cycle.timer ~= nil then S.cycle.timer:stop() end
      S.cycle.timer = timer.doAfter(M.config.cycleTimeout, function() endCycle(true) end)
      log("duyệt sâu -> [%d] %s", target, tostring(e.title))
      return
    end
    table.remove(S.history, target)     -- mục chết: bỏ rồi thử tiếp
  end
  endCycle(false)
end

---------------------------------------------------------------------------
-- Hotkey / eventtap
---------------------------------------------------------------------------
local function enableSafariHotkeys(on)
  for _, hk in pairs(S.hotkeys) do
    if on then hk:enable() else hk:disable() end
  end
  S.hotkeysActive = on
  log("hotkey Safari: %s", on and "BẬT" or "TẮT")
end

local function bindHotkeys()
  if M.config.captureMethod ~= "hotkey" then return end
  if S.hotkeys.switch == nil then
    S.hotkeys.switch = hotkey.new(M.config.switchMods, M.config.switchKey,
      function() M.switchToPrevious() end)
  end
  if M.config.enableDeepCycle and S.hotkeys.deep == nil then
    S.hotkeys.deep = hotkey.new(M.config.deepMods, M.config.deepKey,
      function() M.cycleBack() end)
  end
end

local function startTap()
  if M.config.captureMethod ~= "eventtap" or S.tap ~= nil then return end
  S.tap = eventtap.new({ eventtap.event.types.keyDown }, function(ev)
    if not S.enabled then return false end
    if not isSafariFrontmost() then return false end
    if ev:getKeyCode() ~= keycodes.map[M.config.switchKey] then return false end
    local f = ev:getFlags()
    if f:containExactly(M.config.switchMods) then
      M.switchToPrevious()
      return true
    end
    if M.config.enableDeepCycle and f:containExactly(M.config.deepMods) then
      M.cycleBack()
      return true
    end
    return false
  end)
  S.tap:start()
end

---------------------------------------------------------------------------
-- Observer + timer
---------------------------------------------------------------------------
local APP_NOTIFICATIONS = {
  "AXFocusedUIElementChanged",
  "AXFocusedWindowChanged",
  "AXMainWindowChanged",
  "AXWindowCreated",
  "AXApplicationActivated",
}

local function stopObserver()
  if S.observer ~= nil then
    pcall(function() S.observer:stop() end)
    S.observer = nil
  end
  S.observerPid = nil
  S.watchedWins = {}
end

--- Theo dõi AXTitleChanged trên từng cửa sổ: đổi tab thì tiêu đề cửa sổ đổi theo.
local function refreshWindowWatchers(ae)
  if S.observer == nil or ae == nil then return end
  for i = #S.watchedWins, 1, -1 do
    if not isValid(S.watchedWins[i]) then table.remove(S.watchedWins, i) end
  end
  local wins = attr(ae, "AXWindows")
  if type(wins) ~= "table" then return end
  for _, w in ipairs(wins) do
    local known = false
    for _, kw in ipairs(S.watchedWins) do
      if sameElement(kw, w) then known = true break end
    end
    if not known then
      pcall(function() S.observer:addWatcher(w, "AXTitleChanged") end)
      S.watchedWins[#S.watchedWins + 1] = w
    end
  end
end

local function ensureObserver()
  local app = safariApp()
  if app == nil then stopObserver() return end
  local pid = app:pid()
  if S.observer ~= nil and S.observerPid == pid then return end

  stopObserver()
  local ok, obs = pcall(ax.observer.new, pid)
  if not ok or obs == nil then
    log("không tạo được observer: %s", tostring(obs))
    return
  end
  S.observer, S.observerPid = obs, pid
  obs:callback(function(_, _, notif, _)
    if not S.enabled then return end
    if notif == "AXWindowCreated" then refreshWindowWatchers(appElement()) end
    recordCurrent(false)
  end)

  local ae = ax.applicationElement(app)
  for _, n in ipairs(APP_NOTIFICATIONS) do
    pcall(function() obs:addWatcher(ae, n) end)
  end
  refreshWindowWatchers(ae)
  pcall(function() obs:start() end)
  log("observer đã chạy cho pid %d", pid)
end

local function stopPoller()
  if S.poller ~= nil then
    S.poller:stop()
    S.poller = nil
  end
end

local function startPoller()
  if S.poller ~= nil then return end
  S.poller = timer.doEvery(M.config.pollInterval, function()
    recordCurrent(false)
    local now = timer.secondsSinceEpoch()
    if now - S.lastWinScan > 3 then
      S.lastWinScan = now
      refreshWindowWatchers(appElement())
    end
  end)
end

---------------------------------------------------------------------------
-- Theo dõi ứng dụng phía trước
---------------------------------------------------------------------------
local function onSafariFront(isFront)
  if isFront then
    ensureObserver()
    startPoller()
    if S.enabled then enableSafariHotkeys(true) end
    recordCurrent(true)
  else
    endCycle(true)
    enableSafariHotkeys(false)   -- trả Ctrl+Tab lại cho các app khác
    stopPoller()
  end
end

--- Cửa duy nhất để đổi trạng thái "Safari có đang ở phía trước không".
--- Chỉ làm việc khi trạng thái thực sự đổi, nên gọi bao nhiêu lần cũng rẻ.
local function setFront(isFront)
  if S.frontState == isFront then return end
  S.frontState = isFront
  onSafariFront(isFront)
end

local function startAppWatcher()
  if S.appWatcher ~= nil then return end
  S.appWatcher = appwatcher.new(function(_, ev, app)
    local isSafari = (app ~= nil and app:bundleID() == M.config.bundleID)
    if not isSafari then
      if ev == appwatcher.activated then setFront(false) end
      return
    end
    if ev == appwatcher.activated then
      setFront(true)
    elseif ev == appwatcher.deactivated then
      setFront(false)
    elseif ev == appwatcher.launched then
      ensureObserver()
    elseif ev == appwatcher.terminated then
      S.frontState = false
      stopObserver()
      stopPoller()
      enableSafariHotkeys(false)
      S.history, S.barCache, S.watchedWins = {}, {}, {}
    end
  end)
  S.appWatcher:start()
end

--- Lưới an toàn: hs.application.watcher KHÔNG phát sự kiện `activated` nếu
--- Safari đã sẵn ở phía trước lúc cấu hình được nạp. Không có bộ đồng bộ này
--- thì hotkey có thể nằm im mãi. Mỗi giây chỉ tốn đúng 1 lời gọi rẻ tiền.
local function stopFrontSync()
  if S.frontSync ~= nil then
    S.frontSync:stop()
    S.frontSync = nil
  end
end

local function startFrontSync()
  if S.frontSync ~= nil then return end
  S.frontSync = timer.doEvery(1, function() setFront(isSafariFrontmost()) end)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function M.toggle()
  S.enabled = not S.enabled
  if S.enabled then
    S.frontState = isSafariFrontmost()
    if S.frontState then onSafariFront(true) end
    if M.config.showAlerts then alert.show("Safari MRU Tab: BẬT", 1.0) end
  else
    endCycle(false)
    enableSafariHotkeys(false)
    if M.config.showAlerts then
      alert.show("Safari MRU Tab: TẮT — Ctrl+Tab trở về mặc định", 1.4)
    end
  end
  log("enabled = %s", tostring(S.enabled))
  return S.enabled
end

function M.isEnabled() return S.enabled end

function M.start()
  if S.running then return M end
  S.running = true
  S.enabled = true
  detectEquality()
  bindHotkeys()
  startTap()
  startAppWatcher()
  if S.toggleHotkey == nil then
    S.toggleHotkey = hotkey.bind(M.config.toggleMods, M.config.toggleKey,
      function() M.toggle() end)
  end
  startFrontSync()
  setFront(isSafariFrontmost())
  log("đã khởi động (captureMethod = %s)", M.config.captureMethod)
  return M
end

function M.stop()
  endCycle(false)
  if S.toggleHotkey ~= nil then S.toggleHotkey:delete() S.toggleHotkey = nil end
  for k, hk in pairs(S.hotkeys) do hk:delete() S.hotkeys[k] = nil end
  if S.tap ~= nil then S.tap:stop() S.tap = nil end
  if S.appWatcher ~= nil then S.appWatcher:stop() S.appWatcher = nil end
  stopFrontSync()
  stopPoller()
  stopObserver()
  S.history, S.barCache = {}, {}
  S.frontState = nil
  S.running = false
  return M
end

--- Trạng thái nội bộ, dùng để chẩn đoán.
function M.status()
  return {
    enabled        = S.enabled,
    running        = S.running,
    safariFrontmost= isSafariFrontmost(),
    hotkeysBound   = (S.hotkeys.switch ~= nil),
    hotkeysActive  = S.hotkeysActive,
    observer       = (S.observer ~= nil),
    poller         = (S.poller ~= nil),
    historyCount   = #S.history,
    captureMethod  = M.config.captureMethod,
  }
end

--- In lịch sử tab ra Hammerspoon Console.
function M.dump()
  print(string.format("Safari MRU | enabled=%s | mục=%d | eq=%s | capture=%s",
    tostring(S.enabled), #S.history, tostring(S.eqWorks), M.config.captureMethod))
  for i, e in ipairs(S.history) do
    print(string.format("  %2d. [%s] %-45s idx=%s",
      i, entryAlive(e) and "sống" or "chết", tostring(e.title), tostring(e.index)))
  end
end

--- Kiểm tra Safari có lộ thanh tab qua Accessibility hay không.
--- Chạy trong Hammerspoon Console khi Safari đang mở: require("safari_mru_tabs").probe()
function M.probe()
  local win = focusedWindow()
  if win == nil then print("Không tìm thấy cửa sổ Safari nào.") return end
  print("Cửa sổ: " .. tostring(attr(win, "AXTitle")))
  local bar = tabBarFor(win)
  if bar == nil then
    print("KHÔNG tìm thấy thanh tab — cửa sổ chỉ có 1 tab, hoặc thanh tab đang ẩn")
    print("(Safari > View > Show Tab Bar), hoặc Safari đã đổi cấu trúc Accessibility.")
    return
  end
  local tabs = getTabs(bar)
  print(string.format("Thanh tab: role=%s subrole=%s — %d tab",
    tostring(attr(bar, "AXRole")), tostring(attr(bar, "AXSubrole")), #tabs))
  for i, t in ipairs(tabs) do
    print(string.format("  %2d. asIdx=%-3s value=%-5s %s",
      i, tostring(appleScriptIndex(t, i)), tostring(attr(t, "AXValue")),
      tostring(attr(t, "AXTitle"))))
  end
  local sel, pos = selectedTab(tabs, win)
  print("Tab đang chọn: vị trí " .. tostring(pos) .. " — " ..
    tostring(sel and attr(sel, "AXTitle")))
end

return M
