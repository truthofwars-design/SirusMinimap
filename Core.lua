--=====================================================================
--  SirusMinimap 1.0
--  Квадратная миникарта в стиле ElvUI для WoW 3.3.5a (Sirus)
--  Автор: Миссохота
--=====================================================================

SirusMinimap = {}
local SM = SirusMinimap
local db

local FONT  = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MASK  = "Interface\\ChatFrame\\ChatFrameBackground"
local BLANK = "Interface\\AddOns\\SirusMinimap\\Media\\blank.tga"
local BLIZZ_ARROW = "Interface\\Minimap\\MinimapArrow"
local ACC_R, ACC_G, ACC_B = 0.09, 0.52, 0.82

SM.MAX_FONT  = 16   -- п.5: жёсткий потолок шрифта
SM.MIN_ARROW = 24   -- п.1: стрелка не меньше стандартной, иначе та вылезет из-под неё

----------------------------------------------------------------------
-- Стили стрелки игрока
----------------------------------------------------------------------
-- Стили подкрашиваются через SetVertexColor, поэтому два похожих треугольника
-- после окраски выглядят одинаково. Здесь силуэты заведомо разные.
SM.arrowStyles = {
    { name = "Классическая",   tex = "Interface\\Minimap\\MinimapArrow"          },
    { name = "Карта мира",     tex = "Interface\\WorldMap\\WorldMapArrow"        },
    { name = "Труп",           tex = "Interface\\Minimap\\MiniMap-DeadArrow"     },
    { name = "Транспорт",      tex = "Interface\\Minimap\\MiniMap-VehicleArrow"  },
    { name = "Треугольник UI", tex = "Interface\\Buttons\\Arrow-Up-Up"           },
}

SM.barDirs = {
    { key = "DOWN",  name = "Вниз"   },
    { key = "UP",    name = "Вверх"  },
    { key = "LEFT",  name = "Влево"  },
    { key = "RIGHT", name = "Вправо" },
}

----------------------------------------------------------------------
SM.defaults = {
    size  = 220,
    scale = 1.0,
    posX  = -20,
    posY  = -20,
    locked = true,

    showZone     = true,
    showZoom     = true,
    showCoords   = true,
    showClock    = true,
    clockLocal   = false,
    clockOffset  = 0,      -- ручная поправка серверного времени, часы
    showCalendar = true,   -- стандартная кнопка GameTimeFrame
    showCtrl     = true,

    blizzIconScale = 1.0,  -- размер иконок почты / БГ / поиска подземелий

    collect    = true,
    buttonSize = 26,
    barDir     = 1,

    customArrow    = true,
    hideBlizzArrow = true,   -- п.1
    arrowStyle  = 1,
    arrowSize   = 26,
    arrowR = 1.00, arrowG = 0.82, arrowB = 0.00,
    arrowTex = nil,

    borderR = 0.22, borderG = 0.22, borderB = 0.22,
    fontSize  = 12,
    barAlpha  = 0.55,
    wheelZoom = true,

    hideInCombat   = false,
    hideInInstance = false,
}

----------------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1SirusMinimap|r: " .. tostring(msg))
end
SM.Print = function(self, m) Print(m) end

local hider = CreateFrame("Frame", "SirusMinimapHider", UIParent)
hider:Hide()

-- мягкое убийство: НЕ меняем родителя (иначе ломаются якоря близзардовских панелей)
local function Kill(f, hard)
    if not f then return end
    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    if f.Hide then f:Hide() end
    if hard and f.Hide then f.Show = f.Hide end
    if f.SetAlpha then f:SetAlpha(0) end
    if f.EnableMouse then f:EnableMouse(false) end
    f.smIgnore = true
end

-- жёсткое убийство с переносом (только для чистой декорации)
local function KillHard(f)
    if not f then return end
    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    if f.Hide then f:Hide(); f.Show = f.Hide end
    if f.SetParent then f:SetParent(hider) end
    f.smIgnore = true
end

local BD_FULL = {
    bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local BD_EDGE = { edgeFile = WHITE, edgeSize = 1 }

function SM:Skin(frame, bgAlpha)
    frame:SetBackdrop(BD_FULL)
    frame:SetBackdropColor(0.05, 0.05, 0.05, bgAlpha or 0)
    frame:SetBackdropBorderColor(db.borderR, db.borderG, db.borderB, 1)
    if not frame.smShadow then
        local s = CreateFrame("Frame", nil, frame)
        s:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        s:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        s:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))
        s:SetBackdrop(BD_EDGE)
        s:SetBackdropBorderColor(0, 0, 0, 1)
        s.smIgnore = true
        frame.smShadow = s
    end
    frame.smIgnore = true
    return frame
end

local function SafeToggleWorldMap()
    if InCombatLockdown() then return end
    if type(ToggleWorldMap) == "function" then
        if pcall(ToggleWorldMap) then return end
    end
    if WorldMapFrame then
        if WorldMapFrame:IsShown() then
            pcall(HideUIPanel, WorldMapFrame)
        else
            pcall(ShowUIPanel, WorldMapFrame)
        end
    end
end

-- п.7: штатное окно времени Blizzard (будильник + секундомер)
local function SafeToggleTimeManager()
    if not IsAddOnLoaded("Blizzard_TimeManager") then
        pcall(LoadAddOn, "Blizzard_TimeManager")
    end
    if type(TimeManager_Toggle) == "function" then
        if pcall(TimeManager_Toggle) then return end
    end
    if TimeManagerFrame then
        if TimeManagerFrame:IsShown() then
            pcall(HideUIPanel, TimeManagerFrame)
        else
            pcall(ShowUIPanel, TimeManagerFrame)
        end
        return
    end
    if type(Stopwatch_Toggle) == "function" then pcall(Stopwatch_Toggle) end
end

local function Money(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("|cffffd700%d|rз |cffc7c7cf%d|rс |cffeda55f%d|rм", g, s, c)
end

----------------------------------------------------------------------
-- Тултипы: ВСЕГДА за пределами миникарты (п.3)
----------------------------------------------------------------------
local function AnchorTip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    local h = SM.holder
    if not h then
        GameTooltip:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", 10, -6)
        return
    end
    local cx = h:GetCenter()
    if cx then cx = cx * h:GetEffectiveScale() / UIParent:GetEffectiveScale() end
    if not cx or cx > UIParent:GetWidth() / 2 then
        GameTooltip:SetPoint("TOPRIGHT", h, "TOPLEFT", -8, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", h, "TOPRIGHT", 8, 0)
    end
end
SM.AnchorTip = function(self, f) AnchorTip(f) end

local function Tip(frame, title, ...)
    local lines = { ... }
    AnchorTip(frame)
    GameTooltip:AddLine(title, 1, 1, 1)
    for i = 1, #lines do GameTooltip:AddLine(lines[i], 0.4, 0.7, 1) end
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Чистка стандартного интерфейса
----------------------------------------------------------------------
function SM:CleanBlizzard()
    if MiniMapTrackingDropDown then MiniMapTrackingDropDown:SetParent(UIParent) end

    -- чистая декорация — можно уносить.
    -- ВНИМАНИЕ: MiniMapMailBorder / MiniMapBattlefieldBorder / MiniMapLFGFrameBorder
    -- здесь БОЛЬШЕ НЕТ — это и есть круглые оправы иконок, они должны остаться.
    local hard = {
        MinimapBorder, MinimapBorderTop, MinimapNorthTag,
        MinimapZoomIn, MinimapZoomOut,
        MiniMapWorldMapButton, MinimapZoneTextButton,
        MiniMapTracking, MiniMapTrackingButton, MiniMapTrackingFrame,
        MiniMapVoiceChatFrame,
        MinimapToggleButton,
    }
    for i = 1, #hard do KillHard(hard[i]) end

    -- п.8: стандартные часы. Blizzard_TimeManager грузится ПОЗЖЕ нашего аддона,
    -- поэтому чистку надо повторять — см. обработчик ADDON_LOADED ниже.
    -- Родителя не меняем: к этой кнопке привязано окно TimeManagerFrame.
    Kill(TimeManagerClockButton, true)
    Kill(MiniMapRecordingButton, true)

    if MinimapCluster then
        MinimapCluster:EnableMouse(false)
        MinimapCluster:ClearAllPoints()
        MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
        MinimapCluster:SetWidth(1); MinimapCluster:SetHeight(1)
        MinimapCluster.smIgnore = true
    end
    if MinimapBackdrop then
        MinimapBackdrop.smIgnore = true
        MinimapBackdrop:ClearAllPoints()
        MinimapBackdrop:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    end
end

-- п.11: пользовательский чёрный список фреймов (мигающие красные квадраты и т.п.)
function SM:ApplyHidden()
    if not db.hidden then return end
    for name in pairs(db.hidden) do
        local f = _G[name]
        if f then
            if f.UnregisterAllEvents then f:UnregisterAllEvents() end
            if f.Hide then f:Hide(); f.Show = f.Hide end
            if f.SetAlpha then f:SetAlpha(0) end
            if f.EnableMouse then f:EnableMouse(false) end
            f.smIgnore = true
        end
    end
end

----------------------------------------------------------------------
-- Зум
----------------------------------------------------------------------
function SM:Zoom(delta)
    local z = Minimap:GetZoom() + delta
    local maxZ = Minimap:GetZoomLevels() - 1
    if z < 0 then z = 0 elseif z > maxZ then z = maxZ end
    Minimap:SetZoom(z)
    self:UpdateZoomButtons()
end

-- п.3: состояние кнопок читаем из реального зума, а не запоминаем.
-- Никакой прозрачности — только цвет, кнопки видно всегда.
function SM:UpdateZoomButtons()
    if not self.zoomIn or not self.zoomOut then return end
    local z = Minimap:GetZoom()
    local maxZ = Minimap:GetZoomLevels() - 1

    local function paint(btn, enabled)
        local r, g, b
        if btn.hovered then
            r, g, b = 0.35, 0.75, 1
        elseif enabled then
            r, g, b = 1, 1, 1
        else
            r, g, b = 0.55, 0.55, 0.55
        end
        btn.hbar:SetVertexColor(r, g, b)
        if btn.vbar then btn.vbar:SetVertexColor(r, g, b) end
        btn:SetBackdropColor(0.12, 0.12, 0.12, enabled and 0.95 or 0.55)
    end
    paint(self.zoomIn,  z < maxZ)
    paint(self.zoomOut, z > 0)
end

-- принудительная перерисовка карты после смены размера
function SM:RefreshMinimap()
    Minimap:SetMaskTexture(MASK)
    local z = Minimap:GetZoom()
    local maxZ = Minimap:GetZoomLevels() - 1
    if z < maxZ then Minimap:SetZoom(z + 1) else Minimap:SetZoom(z - 1) end
    Minimap:SetZoom(z)
end

local function WheelHandler(_, delta)
    if not db.wheelZoom then return end
    SM:Zoom(delta > 0 and 1 or -1)
end

----------------------------------------------------------------------
-- Мелкая текстовая кнопка (А П И Н)
----------------------------------------------------------------------
local function MiniButton(parent, w, h, text, r, g, b, onClick, onEnter)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(w); btn:SetHeight(h)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    btn.smIgnore = true
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetFont(FONT, 11, "OUTLINE")
    fs:SetText(text)
    fs:SetTextColor(r, g, b)
    btn.text = fs
    btn.baseR, btn.baseG, btn.baseB = r, g, b
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 1, 1)
        if onEnter then onEnter(self) end
    end)
    btn:SetScript("OnLeave", function(self)
        fs:SetTextColor(self.baseR, self.baseG, self.baseB)
        GameTooltip:Hide()
    end)
    return btn
end

-- п.3: кнопки зума рисуем полосками-текстурами, а не глифом шрифта.
-- Тонкий "-" в FRIZQT просто не читался.
local function ZoomButton(parent, plus, onClick, tipTitle, tipText)
    local b = CreateFrame("Button", nil, parent)
    b.smIgnore = true
    b:SetFrameLevel(parent:GetFrameLevel() + 2)
    b:SetBackdrop(BD_FULL)
    b:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    b:SetBackdropBorderColor(0, 0, 0, 1)

    local hbar = b:CreateTexture(nil, "OVERLAY")
    hbar:SetTexture(WHITE)
    hbar:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.hbar = hbar

    if plus then
        local vbar = b:CreateTexture(nil, "OVERLAY")
        vbar:SetTexture(WHITE)
        vbar:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.vbar = vbar
    end

    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        SM:UpdateZoomButtons()
        Tip(self, tipTitle, tipText)
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        SM:UpdateZoomButtons()
        GameTooltip:Hide()
    end)
    return b
end

----------------------------------------------------------------------
-- Каркас
----------------------------------------------------------------------
function SM:BuildFrames()
    local holder = CreateFrame("Frame", "SirusMinimapHolder", UIParent)
    holder:SetFrameStrata("BACKGROUND")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    holder:EnableMouse(false)
    holder.smIgnore = true
    self.holder = holder

    ------------------------------------------------------------------
    -- Миникарта
    ------------------------------------------------------------------
    Minimap:SetParent(holder)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    Minimap:SetMaskTexture(MASK)
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(2)
    Minimap:EnableMouse(true)
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", WheelHandler)
    Minimap.smIgnore = true

    Minimap:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then
            if MiniMapTrackingDropDown then
                ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, "cursor", 0, 0)
            end
        elseif btn == "MiddleButton" then
            if ToggleCalendar then ToggleCalendar() end
        else
            if Minimap_OnClick then Minimap_OnClick(Minimap) end
        end
    end)

    local border = CreateFrame("Frame", "SirusMinimapBorder", holder)
    border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
    border:SetFrameStrata("LOW")
    border:SetFrameLevel(3)
    self:Skin(border, 0)
    self.border = border

    ------------------------------------------------------------------
    -- ВЕРХНЯЯ ПЛАШКА: [-][+]  Название локации
    ------------------------------------------------------------------
    local top = CreateFrame("Frame", "SirusMinimapTopBar", Minimap)
    top:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -1, -1)
    top:SetHeight(18)
    top:SetFrameStrata("LOW")
    top:SetFrameLevel(6)
    top:EnableMouseWheel(true)
    top:SetScript("OnMouseWheel", WheelHandler)
    local tbg = top:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints(top)
    tbg:SetTexture(0, 0, 0, 1)
    top.bg = tbg
    top.smIgnore = true
    self.topBar = top

    local zout = ZoomButton(top, false, function() SM:Zoom(-1) end,
        "Отдалить", "Показать больше местности")
    zout:SetPoint("LEFT", top, "LEFT", 2, 0)
    self.zoomOut = zout

    local zin = ZoomButton(top, true, function() SM:Zoom(1) end,
        "Приблизить", "Показать меньше местности")
    zin:SetPoint("LEFT", zout, "RIGHT", 2, 0)
    self.zoomIn = zin

    local zt = top:CreateFontString(nil, "OVERLAY")
    zt:SetPoint("LEFT", zin, "RIGHT", 5, 0)
    zt:SetPoint("RIGHT", top, "RIGHT", -4, 0)
    zt:SetJustifyH("CENTER")
    zt:SetFont(FONT, 12, "OUTLINE")
    self.zoneText = zt

    local zoneBtn = CreateFrame("Button", nil, top)
    zoneBtn:SetPoint("LEFT", zin, "RIGHT", 0, 0)
    zoneBtn:SetPoint("RIGHT", top, "RIGHT", 0, 0)
    zoneBtn:SetHeight(18)
    zoneBtn:SetFrameLevel(top:GetFrameLevel() + 1)
    zoneBtn.smIgnore = true
    zoneBtn:SetScript("OnClick", SafeToggleWorldMap)
    zoneBtn:SetScript("OnEnter", function(self)
        AnchorTip(self)
        GameTooltip:AddLine(GetRealZoneText() or "", 1, 1, 1)
        local sub = GetSubZoneText()
        if sub and sub ~= "" then GameTooltip:AddLine(sub, 0.7, 0.7, 0.7) end
        local _, _, faction = GetZonePVPInfo()
        if faction then GameTooltip:AddLine(faction, 0.7, 0.7, 0.7) end
        GameTooltip:AddLine("ЛКМ — карта мира", 0.4, 0.7, 1)
        GameTooltip:Show()
    end)
    zoneBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.zoneBtn = zoneBtn

    ------------------------------------------------------------------
    -- НИЖНЯЯ ПЛАШКА (п.6): [время] [А][П][И][Н] ......... [координаты]
    ------------------------------------------------------------------
    local bot = CreateFrame("Frame", "SirusMinimapBottomBar", Minimap)
    bot:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 1, 1)
    bot:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -1, 1)
    bot:SetHeight(17)
    bot:SetFrameStrata("LOW")
    bot:SetFrameLevel(6)
    bot:EnableMouseWheel(true)
    bot:SetScript("OnMouseWheel", WheelHandler)
    local bbg = bot:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints(bot)
    bbg:SetTexture(0, 0, 0, 1)
    bot.bg = bbg
    bot.smIgnore = true
    self.botBar = bot

    -- 1. ЧАСЫ (крайние слева)
    local clock = CreateFrame("Button", "SirusMinimapClock", bot)
    clock:SetHeight(15); clock:SetWidth(38)
    clock:SetPoint("LEFT", bot, "LEFT", 4, 0)
    clock:SetFrameLevel(bot:GetFrameLevel() + 1)
    clock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    clock.smIgnore = true
    local clt = clock:CreateFontString(nil, "OVERLAY")
    clt:SetPoint("LEFT", clock, "LEFT", 0, 0)
    clt:SetFont(FONT, 11, "OUTLINE")
    clt:SetTextColor(0.85, 0.85, 0.85)
    self.clockText = clt
    clock:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            db.clockLocal = not db.clockLocal
            SM:UpdateClock()
            SM:ClockTooltip(self)
        else
            SafeToggleTimeManager()   -- п.7
        end
    end)
    clock:SetScript("OnEnter", function(self) SM:ClockTooltip(self) end)
    clock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.clockBtn = clock

    -- 2. Кнопки управления — в отдельном контейнере, растянутом между
    --    часами и координатами, чтобы группа стояла ровно по центру (п.6)
    local ctrlHolder = CreateFrame("Frame", nil, bot)
    ctrlHolder:SetHeight(15)
    ctrlHolder:SetFrameLevel(bot:GetFrameLevel() + 1)
    ctrlHolder.smIgnore = true
    self.ctrlHolder = ctrlHolder

    local bAdd = MiniButton(ctrlHolder, 13, 15, "А", 0.45, 0.75, 1.0,
        function()
            SM:CollectButtons()
            SM:ShowIconBar(not SM.iconBar:IsShown())
        end,
        function(s) Tip(s, "Иконки аддонов",
            "Собрано: " .. #SM.collected, "ЛКМ — показать / скрыть") end)

    local bMove = MiniButton(ctrlHolder, 13, 15, "П", 0.45, 0.95, 0.55,
        function() SM:ToggleLock(false) end,
        function(s) Tip(s, "Переместить миникарту",
            "ЛКМ — разблокировать и тащить", "Позиция сохранится сама") end)
    bMove:SetPoint("LEFT", bAdd, "RIGHT", 2, 0)

    local bInfo = MiniButton(ctrlHolder, 13, 15, "И", 1.0, 0.85, 0.35,
        function(s) SM:InfoTooltip(s) end,
        function(s) SM:InfoTooltip(s) end)
    bInfo:SetPoint("LEFT", bMove, "RIGHT", 2, 0)

    local bCfg = MiniButton(ctrlHolder, 13, 15, "Н", 0.80, 0.80, 0.80,
        function() SM:OpenConfig() end,
        function(s) Tip(s, "Настройки SirusMinimap", "ЛКМ — открыть настройки") end)
    bCfg:SetPoint("LEFT", bInfo, "RIGHT", 2, 0)

    self.ctrlButtons = { bAdd, bMove, bInfo, bCfg }

    -- 3. КООРДИНАТЫ (крайние справа)
    local coordBtn = CreateFrame("Button", nil, bot)
    coordBtn:SetHeight(15); coordBtn:SetWidth(76)
    coordBtn:SetPoint("RIGHT", bot, "RIGHT", -4, 0)
    coordBtn:SetFrameLevel(bot:GetFrameLevel() + 1)
    coordBtn.smIgnore = true
    local coords = coordBtn:CreateFontString(nil, "OVERLAY")
    coords:SetPoint("RIGHT", coordBtn, "RIGHT", 0, 0)
    coords:SetJustifyH("RIGHT")
    coords:SetFont(FONT, 11, "OUTLINE")
    coords:SetTextColor(0.85, 0.85, 0.85)
    self.coordText = coords
    coordBtn:SetScript("OnEnter", function(self)
        AnchorTip(self)
        GameTooltip:AddLine("Координаты", 1, 1, 1)
        GameTooltip:AddLine(" ")
        local x, y = GetPlayerMapPosition("player")
        if x and not (x == 0 and y == 0) then
            GameTooltip:AddDoubleLine("Позиция", string.format("%.1f , %.1f", x * 100, y * 100), 1, 1, 1, 0.4, 0.7, 1)
        else
            GameTooltip:AddDoubleLine("Позиция", "недоступна", 1, 1, 1, 0.8, 0.4, 0.4)
        end
        GameTooltip:AddDoubleLine("Зона", GetRealZoneText() or "-", 1, 1, 1, 0.8, 0.8, 0.8)
        local sub = GetSubZoneText()
        if sub and sub ~= "" then
            GameTooltip:AddDoubleLine("Подзона", sub, 1, 1, 1, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("ЛКМ — отправить координаты в чат", 0.4, 0.7, 1)
        GameTooltip:Show()
    end)
    coordBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    coordBtn:SetScript("OnClick", function()
        local x, y = GetPlayerMapPosition("player")
        if x and not (x == 0 and y == 0) and ChatFrame1EditBox then
            ChatEdit_ActivateChat(ChatFrame1EditBox)
            ChatFrame1EditBox:SetText(string.format("%s: %.1f, %.1f",
                GetRealZoneText() or "", x * 100, y * 100))
        end
    end)
    self.coordBtn = coordBtn

    ------------------------------------------------------------------
    -- Стрелка игрока
    ------------------------------------------------------------------
    local af = CreateFrame("Frame", "SirusMinimapArrow", Minimap)
    af:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    af:SetFrameStrata("LOW")
    af:SetFrameLevel(5)
    af.smIgnore = true
    local atex = af:CreateTexture(nil, "OVERLAY")
    atex:SetAllPoints(af)
    self.arrowFrame = af
    self.arrowTex = atex

    ------------------------------------------------------------------
    -- Панель иконок
    ------------------------------------------------------------------
    local bar = CreateFrame("Frame", "SirusMinimapIconBar", holder)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(20)
    self:Skin(bar, 0.85)
    bar:Hide()
    bar:EnableMouse(true)
    self.iconBar = bar
    self.collected = {}

    ------------------------------------------------------------------
    -- Оверлей перемещения
    ------------------------------------------------------------------
    local mover = CreateFrame("Frame", "SirusMinimapMover", UIParent)
    mover:SetAllPoints(holder)
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover.smIgnore = true
    mover:SetBackdrop(BD_FULL)
    mover:SetBackdropColor(ACC_R, ACC_G, ACC_B, 0.40)
    mover:SetBackdropBorderColor(ACC_R, ACC_G, ACC_B, 1)
    local mt = mover:CreateFontString(nil, "OVERLAY")
    mt:SetPoint("CENTER", 0, 18)
    mt:SetFont(FONT, 13, "OUTLINE")
    mt:SetText("Тащи мышью")
    mover:SetScript("OnMouseDown", function() holder:StartMoving() end)
    mover:SetScript("OnMouseUp", function()
        holder:StopMovingOrSizing()
        SM:SavePosition()
    end)
    local lockBtn = CreateFrame("Button", nil, mover, "UIPanelButtonTemplate")
    lockBtn:SetWidth(130); lockBtn:SetHeight(24)
    lockBtn:SetPoint("CENTER", mover, "CENTER", 0, -12)
    lockBtn:SetText("Закрепить здесь")
    lockBtn:SetScript("OnClick", function() SM:ToggleLock(true) end)
    mover:Hide()
    self.mover = mover
end

----------------------------------------------------------------------
-- Позиция
----------------------------------------------------------------------
function SM:SavePosition()
    local h = self.holder
    local s = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    db.posX = (h:GetRight() * s) - UIParent:GetWidth()
    db.posY = (h:GetTop() * s) - UIParent:GetHeight()
    self:ApplyPosition()
    self:LayoutIconBar()
end

function SM:ApplyPosition()
    local h = self.holder
    h:StopMovingOrSizing()
    h:ClearAllPoints()
    h:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", db.posX, db.posY)
end

function SM:ResetPosition()
    db.posX, db.posY = -20, -20
    self:ApplyPosition()
    self:LayoutIconBar()
    Print("Позиция сброшена в правый верхний угол.")
end

----------------------------------------------------------------------
-- п.10: календарь + почта + БГ единой колонкой справа вверху
----------------------------------------------------------------------
-- Порядок колонки под календарём
SM.blizzColumn = {
    "MiniMapMailFrame",
    "MiniMapBattlefieldFrame",
    "MiniMapLFGFrame",
    "MiniMapMeetingStoneFrame",
}

-- Имена, которые почти наверняка относятся к очередям БГ/арены и почте.
-- Такие фреймы висят на MinimapBackdrop и при увеличенной миникарте
-- оказываются у неё в центре — их надо принудительно ставить в колонку.
local columnPatterns = {
    "Battlefield", "Battleground", "PvP", "PVP", "Arena",
    "Queue", "Honor", "Mail", "LFG", "MeetingStone",
}

function SM:LayoutBlizzIcons()
    local barH  = self.topBarHeight or 18
    local scale = db.blizzIconScale or 1.0
    local prev  = nil
    local done  = {}

    -- 1) Календарь Blizzard остаётся ТАМ ЖЕ, ГДЕ БЫЛ.
    --    Не меняем ни родителя, ни якоря, ни масштаб — только видимость.
    if GameTimeFrame then
        GameTimeFrame.smIgnore    = true
        GameTimeFrame.smProtected = true
        GameTimeFrame:SetScale(1)
        done[GameTimeFrame] = true
        if db.showCalendar then
            GameTimeFrame:Show()
            prev = GameTimeFrame
        else
            GameTimeFrame:Hide()
        end
    end

    -- 2) Собираем список кандидатов в нужном порядке
    local list = {}
    local function push(f)
        if f and not done[f] and not f.smCollected then
            done[f] = true
            list[#list + 1] = f
        end
    end

    for i = 1, #self.blizzColumn do push(_G[self.blizzColumn[i]]) end
    if db.attach then
        for name in pairs(db.attach) do push(_G[name]) end
    end

    -- 3) Автопоиск «потеряшек»: всё, что похоже на очередь БГ/почту
    --    и до сих пор болтается на MinimapBackdrop или Minimap
    local roots = { MinimapBackdrop, Minimap }
    for r = 1, #roots do
        if roots[r] then
            local kids = { roots[r]:GetChildren() }
            for i = 1, #kids do
                local f = kids[i]
                local n = f.GetName and f:GetName()
                if n and not done[f] and not f.smCollected
                   and not string.find(n, "SirusMinimap") then
                    for p = 1, #columnPatterns do
                        if string.find(n, columnPatterns[p]) then
                            push(f)
                            break
                        end
                    end
                end
            end
        end
    end

    -- 4) Строим колонку. Скрытые иконки места не занимают:
    --    нет почты — БГ поднимается сразу под календарь.
    for i = 1, #list do
        local f = list[i]
        f.smIgnore    = true
        f.smProtected = true
        f:SetParent(Minimap)
        f:SetScale(scale)
        f:SetFrameStrata("LOW")
        f:SetFrameLevel(8)
        f:ClearAllPoints()
        if prev then
            f:SetPoint("TOP", prev, "BOTTOM", 0, 4)
        else
            f:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -3, -(barH + 3))
        end
        if f:IsShown() then prev = f end
    end

    -- сложность подземелья — в левый верхний угол, чтобы не мешала
    if MiniMapInstanceDifficulty then
        MiniMapInstanceDifficulty.smIgnore = true
        MiniMapInstanceDifficulty.smProtected = true
        MiniMapInstanceDifficulty:SetParent(Minimap)
        MiniMapInstanceDifficulty:ClearAllPoints()
        MiniMapInstanceDifficulty:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -(barH + 3))
        MiniMapInstanceDifficulty:SetFrameStrata("LOW")
        MiniMapInstanceDifficulty:SetFrameLevel(7)
        MiniMapInstanceDifficulty:SetScale(0.85)
    end
end

----------------------------------------------------------------------
-- Тултипы
----------------------------------------------------------------------
function SM:ClockTooltip(anchor)
    AnchorTip(anchor)
    GameTooltip:AddLine("Время", 1, 1, 1)
    GameTooltip:AddLine(" ")
    local h, m = GetGameTime()
    local sr, sg, sb = 0.5, 0.5, 0.5
    local lr, lg, lb = 0.5, 0.5, 0.5
    if db.clockLocal then lr, lg, lb = 0.4, 1, 0.4 else sr, sg, sb = 0.4, 1, 0.4 end
    local off = db.clockOffset or 0
    local sh, sm = h, m
    if off ~= 0 then
        local t = (h * 60 + m + math.floor(off * 60 + 0.5)) % 1440
        if t < 0 then t = t + 1440 end
        sh, sm = math.floor(t / 60), t % 60
    end
    GameTooltip:AddDoubleLine("Сервер",  string.format("%02d:%02d", sh, sm), 1, 1, 1, sr, sg, sb)
    GameTooltip:AddDoubleLine("Местное", date("%H:%M"),                      1, 1, 1, lr, lg, lb)
    GameTooltip:AddLine("Показывается: " ..
        (db.clockLocal and "местное" or "серверное"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(string.format("сырое GetGameTime() = %02d:%02d, поправка %+.1f ч",
        h, m, off), 0.55, 0.55, 0.55)

    local num = GetNumSavedInstances and GetNumSavedInstances() or 0
    if num > 0 then
        local shown = 0
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Сохранения:", 1, 0.82, 0)
        for i = 1, num do
            local name, _, reset, _, locked = GetSavedInstanceInfo(i)
            if locked and reset and reset > 0 then
                if shown < 8 then
                    local d = math.floor(reset / 86400)
                    local hh = math.floor((reset % 86400) / 3600)
                    local t = (d > 0) and string.format("%dд %dч", d, hh) or string.format("%dч", hh)
                    if string.len(name) > 24 then name = string.sub(name, 1, 24) .. "..." end
                    GameTooltip:AddDoubleLine(name, t, 0.9, 0.9, 0.9, 0.7, 0.7, 0.7)
                end
                shown = shown + 1
            end
        end
        if shown > 8 then GameTooltip:AddLine("... и ещё " .. (shown - 8), 0.6, 0.6, 0.6) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("ЛКМ — окно времени Blizzard (будильник, секундомер)", 0.4, 0.7, 1)
    GameTooltip:AddLine("ПКМ — переключить сервер / местное", 0.4, 0.7, 1)
    GameTooltip:Show()
end

local function ColorVal(v, good, mid)
    if v >= good then return 0.2, 1, 0.2
    elseif v >= mid then return 1, 0.82, 0
    else return 1, 0.3, 0.3 end
end

function SM:InfoTooltip(anchor)
    AnchorTip(anchor)
    GameTooltip:AddLine("Информация", 1, 1, 1)
    GameTooltip:AddLine(" ")

    local fps = GetFramerate()
    local r, g, b = ColorVal(fps, 45, 25)
    GameTooltip:AddDoubleLine("FPS", string.format("%.0f", fps), 1, 1, 1, r, g, b)

    local _, _, lag = GetNetStats()
    lag = lag or 0
    r, g, b = ColorVal(300 - lag, 200, 100)
    GameTooltip:AddDoubleLine("Задержка", lag .. " мс", 1, 1, 1, r, g, b)

    local slots = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
    local minDur = 100
    for i = 1, #slots do
        local cur, max = GetInventoryItemDurability(slots[i])
        if cur and max and max > 0 then
            local pr = cur / max * 100
            if pr < minDur then minDur = pr end
        end
    end
    r, g, b = ColorVal(minDur, 60, 25)
    GameTooltip:AddDoubleLine("Прочность", string.format("%.0f%%", minDur), 1, 1, 1, r, g, b)

    local free, total = 0, 0
    for i = 0, 4 do
        local s = GetContainerNumSlots(i)
        if s and s > 0 then
            total = total + s
            free = free + (GetContainerNumFreeSlots(i) or 0)
        end
    end
    r, g, b = ColorVal(free, 15, 5)
    GameTooltip:AddDoubleLine("Свободно в сумках", free .. " / " .. total, 1, 1, 1, r, g, b)

    GameTooltip:AddDoubleLine("Деньги", Money(GetMoney()), 1, 1, 1, 1, 1, 1)

    if UpdateAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        local mem = 0
        for i = 1, GetNumAddOns() do mem = mem + (GetAddOnMemoryUsage(i) or 0) end
        GameTooltip:AddDoubleLine("Память аддонов", string.format("%.1f МБ", mem / 1024), 1, 1, 1, 0.8, 0.8, 0.8)
    end

    local s = GetTime() - (SM.loginTime or GetTime())
    GameTooltip:AddDoubleLine("В игре этот сеанс",
        string.format("%d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60)),
        1, 1, 1, 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

----------------------------------------------------------------------
-- Обновления
----------------------------------------------------------------------
local pvpColors = {
    sanctuary = { 0.41, 0.80, 0.94 },
    arena     = { 1.00, 0.10, 0.10 },
    friendly  = { 0.10, 1.00, 0.10 },
    hostile   = { 1.00, 0.10, 0.10 },
    contested = { 1.00, 0.70, 0.00 },
}

-- п.2: шрифт локации теперь ставится ВСЕГДА, а не только если удалось
-- прочитать ширину FontString'а (она бывает 0 и старый код молча выходил).
function SM:UpdateZone()
    if not self.zoneText then return end
    local txt = GetMinimapZoneText() or ""
    local pvp = GetZonePVPInfo()
    local c = pvpColors[pvp or ""] or { 1, 1, 1 }
    self.zoneText:SetText(txt)
    self.zoneText:SetTextColor(c[1], c[2], c[3])

    local size = math.min(db.fontSize or 12, SM.MAX_FONT)
    self.zoneText:SetFont(FONT, size, "OUTLINE")

    local maxW = self.zoneWidth or 0
    if maxW > 20 then
        while size > 7 and self.zoneText:GetStringWidth() > maxW do
            size = size - 1
            self.zoneText:SetFont(FONT, size, "OUTLINE")
        end
    end
end

local needMapReset = true
function SM:UpdateCoords()
    if not self.coordText or not db.showCoords then return end
    if needMapReset and not (WorldMapFrame and WorldMapFrame:IsShown()) then
        SetMapToCurrentZone()
        needMapReset = false
    end
    local x, y = GetPlayerMapPosition("player")
    if not x or (x == 0 and y == 0) then
        self.coordText:SetText("|cff777777--.- --.-|r")
        needMapReset = true
    else
        self.coordText:SetFormattedText("%.1f  %.1f", x * 100, y * 100)
    end
    self.coordBtn:SetWidth(math.max(38, self.coordText:GetStringWidth() + 4))
end

-- п.9: никакой буквы "м". Режим виден в тултипе.
function SM:UpdateClock()
    if not self.clockText then return end
    local h, m
    if db.clockLocal then
        h, m = tonumber(date("%H")), tonumber(date("%M"))
    else
        h, m = GetGameTime()
        -- Sirus иногда отдаёт в GetGameTime() время клиента, а не реалма.
        -- Ручная поправка гарантированно приводит часы к нужному поясу.
        local off = db.clockOffset or 0
        if h and off ~= 0 then
            local t = (h * 60 + m + math.floor(off * 60 + 0.5)) % 1440
            if t < 0 then t = t + 1440 end
            h, m = math.floor(t / 60), t % 60
        end
    end
    if not h then return end
    self.clockText:SetFormattedText("|cffffffff%02d|r:|cffffffff%02d|r", h, m)
    self.clockBtn:SetWidth(math.max(28, self.clockText:GetStringWidth() + 4))
end

local function SetTexRotation(tex, a)
    local c, s = math.cos(a), math.sin(a)
    tex:SetTexCoord(
        0.5 - 0.5 * c + 0.5 * s, 0.5 - 0.5 * s - 0.5 * c,
        0.5 - 0.5 * c - 0.5 * s, 0.5 - 0.5 * s + 0.5 * c,
        0.5 + 0.5 * c + 0.5 * s, 0.5 + 0.5 * s - 0.5 * c,
        0.5 + 0.5 * c - 0.5 * s, 0.5 + 0.5 * s + 0.5 * c
    )
end

-- п.1: гасим движковую стрелку прозрачной текстурой
function SM:ApplyBlizzArrow()
    if not Minimap.SetPlayerTexture then return false end
    if db.customArrow and db.hideBlizzArrow then
        return pcall(Minimap.SetPlayerTexture, Minimap, BLANK)
    end
    return pcall(Minimap.SetPlayerTexture, Minimap, BLIZZ_ARROW)
end

function SM:UpdateArrow()
    if not self.arrowFrame then return end
    if not db.customArrow then self.arrowFrame:Hide() return end
    self.arrowFrame:Show()
    local style = self.arrowStyles[db.arrowStyle] or self.arrowStyles[1]
    local sz = math.max(SM.MIN_ARROW, db.arrowSize or SM.MIN_ARROW)
    self.arrowFrame:SetWidth(sz)
    self.arrowFrame:SetHeight(sz)
    self.arrowTex:SetTexture(db.arrowTex or style.tex)
    self.arrowTex:SetVertexColor(db.arrowR, db.arrowG, db.arrowB)
    local facing = GetPlayerFacing and GetPlayerFacing()
    if GetCVar("rotateMinimap") == "1" then facing = 0 end
    SetTexRotation(self.arrowTex, facing or 0)
end

----------------------------------------------------------------------
-- Сборщик иконок аддонов
----------------------------------------------------------------------
local ignoreNames = {
    MinimapPing = true, MinimapBackdrop = true, MinimapZoneTextButton = true,
    MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true,
    MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
    MiniMapMailFrame = true, MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true,
    MiniMapInstanceDifficulty = true, MiniMapVoiceChatFrame = true,
    GameTimeFrame = true, TimeManagerClockButton = true, MinimapNorthTag = true,
    MinimapCluster = true, MiniMapMeetingStoneFrame = true, MinimapZoneText = true,
    Minimap = true, MiniMapRecordingButton = true,
}

-- п.10: расширенный фильтр, чтобы БГ/почта/календарь не попадали в панель "А"
local badPatterns = {
    "Recording", "POI", "Poi", "Blip", "Ping", "Compass", "North",
    "Cluster", "Backdrop", "Difficulty", "Tracking", "ZoneText",
    "VoiceChat", "GameTime", "TimeManager", "Clock", "Zoom", "WorldMapButton",
    "SirusMinimap", "Marker", "Pin", "Nameplate", "Vehicle", "Arrow",
    "MailFrame", "Mail", "Battlefield", "Battleground", "PvP", "PVP",
    "Honor", "Arena", "Queue", "LFG", "MeetingStone", "Corpse", "Calendar",
}

local function IsAddonButton(f)
    if not f or f.smCollected or f.smIgnore or f.smProtected then return false end
    if not f:IsShown() then return false end

    local name = f.GetName and f:GetName()
    if not name then return false end
    if ignoreNames[name] then return false end
    if db.noCollect and db.noCollect[name] then return false end
    for i = 1, #badPatterns do
        if string.find(name, badPatterns[i]) then return false end
    end

    local ot = f:GetObjectType()
    if ot ~= "Button" and ot ~= "Frame" then return false end
    if not f:IsMouseEnabled() then return false end

    local clickable
    if ot == "Button" then
        clickable = f:GetScript("OnClick") or f:GetScript("OnMouseUp") or f:GetScript("OnMouseDown")
    else
        clickable = f:GetScript("OnMouseUp") or f:GetScript("OnMouseDown")
    end
    if not clickable then return false end

    local w, h = f:GetWidth(), f:GetHeight()
    if not w or not h then return false end
    if w < 12 or w > 60 or h < 12 or h > 60 then return false end
    return true
end

function SM:CollectButtons()
    if not db.collect then return 0 end
    local parents = { Minimap, MinimapBackdrop }
    local found = 0
    for p = 1, #parents do
        if parents[p] then
            local kids = { parents[p]:GetChildren() }
            for i = 1, #kids do
                local b = kids[i]
                if IsAddonButton(b) then
                    b.smCollected = true
                    b.smSetPoint = b.SetPoint
                    b.smClearAllPoints = b.ClearAllPoints
                    -- запоминаем СОБСТВЕННЫЙ размер кнопки: дальше её
                    -- масштабируем, а не растягиваем (иначе оправа и иконка
                    -- остаются прежними и появляются щели / нахлёст)
                    b.smNaturalW = math.max(8, b:GetWidth() or 31, b:GetHeight() or 31)

                    local cell = CreateFrame("Frame", nil, self.iconBar)
                    cell:SetFrameStrata("MEDIUM")
                    cell:SetFrameLevel(21)
                    cell.smIgnore = true
                    b.smCell = cell

                    b:SetParent(cell)
                    b:SetScript("OnDragStart", nil)
                    b:SetScript("OnDragStop", nil)
                    b:SetFrameStrata("MEDIUM")
                    b:SetFrameLevel(22)
                    b.smClearAllPoints(b)
                    b.smSetPoint(b, "CENTER", cell, "CENTER", 0, 0)
                    b.SetPoint = function() end
                    b.ClearAllPoints = function() end

                    table.insert(self.collected, b)
                    found = found + 1
                end
            end
        end
    end
    if found > 0 then self:LayoutIconBar() end
    return found
end

function SM:LayoutIconBar()
    local bar = self.iconBar
    if not bar then return end
    local n = #self.collected
    local size = db.buttonSize
    local pad  = 3
    local dir  = (self.barDirs[db.barDir] or self.barDirs[1]).key
    local vertical = (dir == "LEFT" or dir == "RIGHT")

    -- ячейка ровно size x size, кнопка внутри масштабируется под неё
    local function place(i, x, y)
        local b = self.collected[i]
        local cell = b.smCell
        if not cell then return end
        cell:SetWidth(size); cell:SetHeight(size)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
        b:SetScale(size / (b.smNaturalW or 31))
    end

    if vertical then
        local barH   = db.size
        local perCol = math.max(1, math.floor((barH - pad) / (size + pad)))
        local cols   = math.max(1, math.ceil(math.max(n, 1) / perCol))
        bar:SetHeight(barH)
        bar:SetWidth(cols * (size + pad) + pad)
        for i = 1, n do
            local col   = math.floor((i - 1) / perCol)
            local cnt   = math.min(perCol, n - col * perCol)
            local row   = (i - 1) % perCol
            local colH  = cnt * (size + pad) - pad
            local startY = (barH - colH) / 2
            place(i, pad + col * (size + pad), startY + row * (size + pad))
        end
    else
        local barW   = db.size
        local perRow = math.max(1, math.floor((barW - pad) / (size + pad)))
        local rows   = math.max(1, math.ceil(math.max(n, 1) / perRow))
        bar:SetWidth(barW)
        bar:SetHeight(rows * (size + pad) + pad)
        for i = 1, n do
            local row   = math.floor((i - 1) / perRow)
            local cnt   = math.min(perRow, n - row * perRow)
            local col   = (i - 1) % perRow
            local rowW  = cnt * (size + pad) - pad
            local startX = (barW - rowW) / 2
            place(i, startX + col * (size + pad), pad + row * (size + pad))
        end
    end

    bar:ClearAllPoints()
    if dir == "UP" then
        bar:SetPoint("BOTTOMLEFT", self.holder, "TOPLEFT", 0, 4)
    elseif dir == "LEFT" then
        bar:SetPoint("TOPRIGHT", self.holder, "TOPLEFT", -4, 0)
    elseif dir == "RIGHT" then
        bar:SetPoint("TOPLEFT", self.holder, "TOPRIGHT", 4, 0)
    else
        bar:SetPoint("TOPLEFT", self.holder, "BOTTOMLEFT", 0, -4)
    end
end

function SM:ShowIconBar(show)
    if not self.iconBar then return end
    if show then
        self:LayoutIconBar()
        self.iconBar:Show()
        if #self.collected == 0 then
            Print("Иконок аддонов пока не найдено — они появляются в течение минуты после входа.")
        end
    else
        self.iconBar:Hide()
    end
end

----------------------------------------------------------------------
-- п.11: диагностика мусора на миникарте
----------------------------------------------------------------------
function SM:Dump()
    Print("|cffffd700--- Фреймы на миникарте ---|r")
    local seen = 0
    local parents = { Minimap, MinimapBackdrop, MinimapCluster }
    for p = 1, #parents do
        if parents[p] then
            local kids = { parents[p]:GetChildren() }
            for i = 1, #kids do
                local f = kids[i]
                local n = (f.GetName and f:GetName()) or "|cff888888(без имени)|r"
                seen = seen + 1
                Print(string.format("%d) %s [%s] %dx%d %s", seen, n, f:GetObjectType(),
                    math.floor(f:GetWidth() or 0), math.floor(f:GetHeight() or 0),
                    f:IsShown() and "|cff40ff40показан|r" or "|cff888888скрыт|r"))
            end
        end
    end
    Print("|cffffd700--- Текстуры прямо на Minimap ---|r")
    local regs = { Minimap:GetRegions() }
    for i = 1, #regs do
        local r = regs[i]
        if r.GetObjectType and r:GetObjectType() == "Texture" then
            Print(string.format("T%d) %s -> %s %s", i,
                (r.GetName and r:GetName()) or "(без имени)",
                tostring(r:GetTexture()),
                r:IsShown() and "показана" or "скрыта"))
        end
    end
    Print("Скрыть лишнее: |cff1784d1/smm hide ИмяФрейма|r , вернуть: |cff1784d1/smm show ИмяФрейма|r")
end

----------------------------------------------------------------------
-- Видимость
----------------------------------------------------------------------
-- InCombatLockdown() в 3.3.5 на самом событии PLAYER_REGEN_DISABLED
-- ещё возвращает false — поэтому состояние боя держим сами.
SM.inCombat = false

function SM:UpdateVisibility()
    local hide = false
    if db.hideInCombat and (self.inCombat or InCombatLockdown()) then hide = true end
    if db.hideInInstance and IsInInstance() then hide = true end
    if hide then self.holder:Hide() else self.holder:Show() end
end

----------------------------------------------------------------------
-- Применение настроек
----------------------------------------------------------------------
function SM:UpdateAll()
    -- жёсткие лимиты (п.1 и п.5)
    if db.fontSize  > SM.MAX_FONT  then db.fontSize  = SM.MAX_FONT  end
    if db.fontSize  < 8            then db.fontSize  = 8            end
    if db.arrowSize < SM.MIN_ARROW then db.arrowSize = SM.MIN_ARROW end

    local size = db.size
    self.holder:SetScale(db.scale)
    self.holder:SetWidth(size)
    self.holder:SetHeight(size)
    self:ApplyPosition()

    Minimap:SetWidth(size)
    Minimap:SetHeight(size)

    self.border:SetBackdropBorderColor(db.borderR, db.borderG, db.borderB, 1)
    self.iconBar:SetBackdropBorderColor(db.borderR, db.borderG, db.borderB, 1)

    self.topBar.bg:SetTexture(0, 0, 0, db.barAlpha)
    self.botBar.bg:SetTexture(0, 0, 0, db.barAlpha)

    local barH = math.max(17, db.fontSize + 7)
    self.topBarHeight = barH
    self.topBar:SetHeight(barH)
    self.botBar:SetHeight(barH)
    self.zoneBtn:SetHeight(barH)

    ------------------------------------------------------------------
    -- Кнопки зума (п.3)
    ------------------------------------------------------------------
    local zs = barH - 4
    local barLen = math.floor(zs * 0.55)
    local barTh  = math.max(2, math.floor(zs / 7))
    for _, b in ipairs({ self.zoomOut, self.zoomIn }) do
        b:SetWidth(zs); b:SetHeight(zs)
        b.hbar:SetWidth(barLen); b.hbar:SetHeight(barTh)
        if b.vbar then b.vbar:SetWidth(barTh); b.vbar:SetHeight(barLen) end
    end

    local zoomBlock = db.showZoom and (zs * 2 + 6) or 0
    self.zoneWidth = size - zoomBlock - 14

    ------------------------------------------------------------------
    -- Нижняя плашка (п.6): время -> А П И Н -> координаты
    ------------------------------------------------------------------
    self.clockBtn:SetHeight(barH - 2)
    self.coordBtn:SetHeight(barH - 2)
    self.coordText:SetFont(FONT, db.fontSize - 1, "OUTLINE")
    self.clockText:SetFont(FONT, db.fontSize - 1, "OUTLINE")
    self:UpdateClock()
    self:UpdateCoords()

    -- ширина группы А П И Н подстраивается под свободное место,
    -- чтобы она не наезжала на координаты на узкой миникарте
    local gap = 2
    local cw  = math.max(13, db.fontSize + 2)
    local used = 18
    if db.showClock  then used = used + self.clockBtn:GetWidth() end
    if db.showCoords then used = used + self.coordBtn:GetWidth() end
    local avail = size - used
    if 4 * cw + 3 * gap > avail then
        cw = math.max(9, math.floor((avail - 3 * gap) / 4))
    end
    local groupW = 4 * cw + 3 * gap

    for i = 1, #self.ctrlButtons do
        self.ctrlButtons[i]:SetWidth(cw)
        self.ctrlButtons[i]:SetHeight(barH - 2)
        self.ctrlButtons[i].text:SetFont(FONT, math.min(db.fontSize - 1, cw), "OUTLINE")
    end
    self.ctrlHolder:SetHeight(barH - 2)

    if db.showZoom then self.zoomIn:Show(); self.zoomOut:Show()
    else self.zoomIn:Hide(); self.zoomOut:Hide() end
    if db.showZone then self.zoneText:Show(); self.zoneBtn:Show()
    else self.zoneText:Hide(); self.zoneBtn:Hide() end
    if db.showZone or db.showZoom then self.topBar:Show() else self.topBar:Hide() end

    for i = 1, #self.ctrlButtons do
        if db.showCtrl then self.ctrlButtons[i]:Show() else self.ctrlButtons[i]:Hide() end
    end
    if db.showCoords then self.coordBtn:Show() else self.coordBtn:Hide() end
    if db.showClock then self.clockBtn:Show() else self.clockBtn:Hide() end
    if db.showCtrl or db.showCoords or db.showClock then
        self.botBar:Show()
    else
        self.botBar:Hide()
    end

    -- порядок слева направо: часы -> А П И Н (по центру) -> координаты
    self.ctrlHolder:ClearAllPoints()
    if db.showClock then
        self.ctrlHolder:SetPoint("LEFT", self.clockBtn, "RIGHT", 4, 0)
    else
        self.ctrlHolder:SetPoint("LEFT", self.botBar, "LEFT", 4, 0)
    end
    if db.showCoords then
        self.ctrlHolder:SetPoint("RIGHT", self.coordBtn, "LEFT", -4, 0)
    else
        self.ctrlHolder:SetPoint("RIGHT", self.botBar, "RIGHT", -4, 0)
    end
    self.ctrlButtons[1]:ClearAllPoints()
    self.ctrlButtons[1]:SetPoint("CENTER", self.ctrlHolder, "CENTER", -(groupW - cw) / 2, 0)

    self:UpdateArrow()
    self:ApplyBlizzArrow()
    self:UpdateZone()
    self:UpdateClock()
    self:LayoutBlizzIcons()
    self:LayoutIconBar()
    self:UpdateVisibility()
    self:RefreshMinimap()
    self:UpdateZoomButtons()
    self.pendingRefresh = 3

    if db.locked then self.mover:Hide() else self.mover:Show() end
end

function SM:ToggleLock(state)
    if state == nil then state = not db.locked end
    db.locked = state
    if db.locked then
        self:SavePosition()
        self.mover:Hide()
        Print("Миникарта закреплена, позиция сохранена.")
    else
        self.mover:Show()
        Print("Тащи миникарту мышью, затем нажми |cff1784d1Закрепить здесь|r.")
    end
end

function SM:OpenConfig()
    if InterfaceOptionsFrame_OpenToCategory and SM.optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(SM.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(SM.optionsPanel)
    end
end

----------------------------------------------------------------------
-- Таймеры
----------------------------------------------------------------------
local tArrow, tCoord, tClock, tScan, tGuard, scans = 0, 0, 0, 0, 0, 0
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, e)
    if SM.pendingRefresh and SM.pendingRefresh > 0 then
        SM.pendingRefresh = SM.pendingRefresh - 1
        SM:RefreshMinimap()
    end
    tArrow = tArrow + e
    if tArrow > 0.03 then
        tArrow = 0
        if db.customArrow then SM:UpdateArrow() end
    end
    tCoord = tCoord + e
    if tCoord > 0.15 then
        tCoord = 0
        SM:UpdateCoords()
        SM:UpdateZoomButtons()   -- п.3: ловим зум из других источников
    end
    tClock = tClock + e
    if tClock > 1 then tClock = 0; SM:UpdateClock() end
    tGuard = tGuard + e
    if tGuard > 2 then
        tGuard = 0
        SM:ApplyHidden()
        -- иконка очереди БГ/арены создаётся движком поздно и сама себя
        -- переанкорит при смене статуса — поэтому колонку пересобираем
        SM:LayoutBlizzIcons()
        if TimeManagerClockButton and TimeManagerClockButton:IsShown() then
            Kill(TimeManagerClockButton, true)   -- п.8
        end
    end
    if scans < 12 then
        tScan = tScan + e
        if tScan > 5 then
            tScan = 0
            scans = scans + 1
            SM:CollectButtons()
        end
    end
end)

----------------------------------------------------------------------
-- Слэш-команды
----------------------------------------------------------------------
SLASH_SIRUSMINIMAP1 = "/smm"
SLASH_SIRUSMINIMAP2 = "/sirusminimap"
SlashCmdList["SIRUSMINIMAP"] = function(msg)
    msg = msg or ""
    local cmd, arg = string.match(msg, "^(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "lock" then SM:ToggleLock(true)
    elseif cmd == "unlock" or cmd == "move" then SM:ToggleLock(false)
    elseif cmd == "reset" then SM:ResetPosition()
    elseif cmd == "scan" then Print("Найдено новых иконок: " .. (SM:CollectButtons() or 0))
    elseif cmd == "dump" then SM:Dump()

    elseif cmd == "hide" then
        if arg == "" then Print("Формат: /smm hide ИмяФрейма") return end
        db.hidden[arg] = true
        SM:ApplyHidden()
        Print("Скрыт: " .. arg .. " (нужен /reload, если фрейм уже нарисован)")

    elseif cmd == "show" then
        if arg == "" then Print("Формат: /smm show ИмяФрейма") return end
        db.hidden[arg] = nil
        Print("Возвращён: " .. arg .. " — нужен /reload")

    elseif cmd == "attach" then
        if arg == "" then Print("Формат: /smm attach ИмяФрейма") return end
        db.attach[arg] = true
        SM:LayoutBlizzIcons()
        Print("Поставлено в колонку под календарём: " .. arg)

    elseif cmd == "unattach" then
        if arg == "" then Print("Формат: /smm unattach ИмяФрейма") return end
        db.attach[arg] = nil
        Print("Убрано из колонки: " .. arg .. " — нужен /reload")

    elseif cmd == "skip" then
        if arg == "" then Print("Формат: /smm skip ИмяФрейма") return end
        db.noCollect[arg] = true
        Print("Не собирать в панель «А»: " .. arg .. " — нужен /reload")

    elseif cmd == "unskip" then
        if arg == "" then Print("Формат: /smm unskip ИмяФрейма") return end
        db.noCollect[arg] = nil
        Print("Снова собирается: " .. arg .. " — нужен /reload")

    elseif cmd == "arrowtex" then
        db.arrowTex = (arg ~= "" and arg) or nil
        SM:UpdateArrow()
        Print("Текстура стрелки: " .. (db.arrowTex or "стандартная"))

    elseif cmd == "default" then
        for k, v in pairs(SM.defaults) do
            if type(v) ~= "table" then SirusMinimapDB[k] = v end
        end
        SirusMinimapDB.arrowTex = nil
        SM:UpdateAll()
        if SM.RefreshConfig then SM:RefreshConfig() end
        Print("Настройки сброшены.")

    elseif cmd == "help" or cmd == "?" then
        Print("dump — список фреймов на карте | hide/show Имя — скрыть/вернуть")
        Print("attach/unattach Имя — поставить иконку в колонку под календарём")
        Print("skip/unskip Имя — исключить из панели «А» | reset | scan | default")

    else SM:OpenConfig() end
end

----------------------------------------------------------------------
-- Загрузка
----------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("ZONE_CHANGED")
ef:RegisterEvent("ZONE_CHANGED_INDOORS")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ef.RegisterEvent, ef, "CALENDAR_UPDATE_PENDING_INVITES")
-- мгновенная перестройка колонки, когда появляется/исчезает иконка
pcall(ef.RegisterEvent, ef, "UPDATE_BATTLEFIELD_STATUS")
pcall(ef.RegisterEvent, ef, "UPDATE_PENDING_MAIL")
pcall(ef.RegisterEvent, ef, "MAIL_INBOX_UPDATE")
pcall(ef.RegisterEvent, ef, "LFG_UPDATE")

ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "SirusMinimap" then
            SirusMinimapDB = SirusMinimapDB or {}
            for k, v in pairs(SM.defaults) do
                if type(v) ~= "table" and SirusMinimapDB[k] == nil then
                    SirusMinimapDB[k] = v
                end
            end
            SirusMinimapDB.hidden    = SirusMinimapDB.hidden or {}
            SirusMinimapDB.noCollect = SirusMinimapDB.noCollect or {}
            SirusMinimapDB.attach    = SirusMinimapDB.attach or {}

            db = SirusMinimapDB
            SM.db = db
            SM.loginTime = GetTime()
            if db.arrowStyle > #SM.arrowStyles then db.arrowStyle = 1 end
            if db.barDir > #SM.barDirs then db.barDir = 1 end
            if db.fontSize  > SM.MAX_FONT  then db.fontSize  = SM.MAX_FONT  end
            if db.arrowSize < SM.MIN_ARROW then db.arrowSize = SM.MIN_ARROW end

            SM:CleanBlizzard()
            SM:BuildFrames()
            if SM.BuildConfig then SM:BuildConfig() end
            SM:UpdateAll()
            SM:ApplyHidden()
            driver:Show()
            Print("загружен. |cff1784d1/smm help|r — команды, |cff1784d1/smm dump|r — поиск мусора на карте.")

        elseif db then
            -- п.8: Blizzard_TimeManager и часть UI Sirus грузятся ПОСЛЕ нас
            Kill(TimeManagerClockButton, true)
            Kill(MiniMapRecordingButton, true)
            SM:ApplyHidden()
            SM:LayoutBlizzIcons()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        needMapReset = true
        SM:CleanBlizzard()
        SM:ApplyHidden()
        SM:LayoutBlizzIcons()
        SM:ApplyBlizzArrow()
        SM:UpdateZone()
        SM:CollectButtons()
        SM:UpdateVisibility()
        SM.pendingRefresh = 3
        if RequestRaidInfo then RequestRaidInfo() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        SM.inCombat = true
        SM:UpdateVisibility()

    elseif event == "PLAYER_REGEN_ENABLED" then
        SM.inCombat = false
        SM:UpdateVisibility()

    elseif event == "UPDATE_BATTLEFIELD_STATUS" or event == "UPDATE_PENDING_MAIL"
        or event == "MAIL_INBOX_UPDATE" or event == "LFG_UPDATE" then
        SM:LayoutBlizzIcons()

    elseif event == "CALENDAR_UPDATE_PENDING_INVITES" then
        -- обрабатывает сам GameTimeFrame

    else
        needMapReset = true
        SM:UpdateZone()
    end
end)
