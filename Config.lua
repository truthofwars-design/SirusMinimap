--=====================================================================
--  SirusMinimap - панель настроек
--=====================================================================

local SM = SirusMinimap
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local idx = 0
local function UID() idx = idx + 1 return "SirusMinimapCfg" .. idx end

-- Реестр «перечитать значение из базы».
-- Без него после сброса виджеты показывают старое, а любое касание
-- слайдера возвращает старое значение обратно в базу.
local refreshers = {}

----------------------------------------------------------------------
local function Header(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText("|cff1784d1" .. text .. "|r")
    return fs
end

local function Check(parent, x, y, label, key, tip)
    local cb = CreateFrame("CheckButton", UID(), parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetWidth(24); cb:SetHeight(24)
    local t = _G[cb:GetName() .. "Text"]
    t:SetText(label)
    t:SetFontObject("GameFontHighlightSmall")
    cb:SetChecked(SM.db[key])
    cb:SetScript("OnClick", function(self)
        SM.db[key] = self:GetChecked() and true or false
        SM:UpdateAll()
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table.insert(refreshers, function() cb:SetChecked(SM.db[key]) end)
    return cb
end

local function Slider(parent, x, y, label, key, minV, maxV, step, width, fmt)
    local name = UID()
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 6, y)
    s:SetWidth(width or 230)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    local title = _G[name .. "Text"]

    local lock = false
    local function setLabel(v)
        title:SetText(label .. ": |cffffffff" .. string.format(fmt or "%d", v) .. "|r")
    end
    local function pull()
        local cur = SM.db[key] or minV
        if cur < minV then cur = minV elseif cur > maxV then cur = maxV end
        lock = true
        s:SetValue(cur)
        lock = false
        setLabel(cur)
    end

    pull()
    s:SetScript("OnValueChanged", function(_, v)
        if lock then return end
        v = math.floor(v / step + 0.5) * step
        if v < minV then v = minV elseif v > maxV then v = maxV end
        SM.db[key] = v
        setLabel(v)
        SM:UpdateAll()
    end)
    table.insert(refreshers, pull)
    return s
end

local function ColorSwatch(parent, x, y, label, rk, gk, bk)
    local b = CreateFrame("Button", UID(), parent)
    b:SetWidth(20); b:SetHeight(20)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropBorderColor(0, 0, 0, 1)
    b:SetBackdropColor(SM.db[rk], SM.db[gk], SM.db[bk], 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    fs:SetText(label)
    b:SetScript("OnClick", function()
        local old = { SM.db[rk], SM.db[gk], SM.db[bk] }
        local function apply()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            SM.db[rk], SM.db[gk], SM.db[bk] = r, g, bl
            b:SetBackdropColor(r, g, bl, 1)
            SM:UpdateAll()
        end
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = function()
            SM.db[rk], SM.db[gk], SM.db[bk] = old[1], old[2], old[3]
            b:SetBackdropColor(old[1], old[2], old[3], 1)
            SM:UpdateAll()
        end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(old[1], old[2], old[3])
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end)
    -- вот этого и не хватало: образец цвета не перечитывался после сброса
    table.insert(refreshers, function()
        b:SetBackdropColor(SM.db[rk], SM.db[gk], SM.db[bk], 1)
    end)
    return b
end

local function Btn(parent, x, y, w, label, onClick)
    local b = CreateFrame("Button", UID(), parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y)
    b:SetWidth(w); b:SetHeight(22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

----------------------------------------------------------------------
local function RefreshAll()
    for i = 1, #refreshers do refreshers[i]() end
end

local function ResetAll()
    for k, v in pairs(SM.defaults) do
        if type(v) ~= "table" then SirusMinimapDB[k] = v end
    end
    SirusMinimapDB.arrowTex = nil
    SM:UpdateAll()
    RefreshAll()
    SM:Print("Все настройки сброшены на стандартные.")
end

----------------------------------------------------------------------
function SM:BuildConfig()
    local p = CreateFrame("Frame", "SirusMinimapOptions", UIParent)
    p.name = "SirusMinimap"
    SM.optionsPanel = p

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("SirusMinimap |cff888888v1.0|r")

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("|cffaaaaaaАвтор: Миссохота  |  Нижняя плашка: время — А П И Н — координаты|r")

    ------------------------------------------------------------------
    -- Прокрутка: опций стало много, в один экран они больше не влезают
    ------------------------------------------------------------------
    local scroll = CreateFrame("ScrollFrame", "SirusMinimapOptionsScroll", p,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -58)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -30, 8)

    local c = CreateFrame("Frame", "SirusMinimapOptionsContent", scroll)
    c:SetWidth(560)
    c:SetHeight(700)
    scroll:SetScrollChild(c)

    ------------------------------------------------------------------
    -- ЛЕВАЯ КОЛОНКА
    ------------------------------------------------------------------
    local L, y = 8, -8

    Header(c, L, y, "Элементы"); y = y - 24
    Check(c, L, y, "Название локации", "showZone",
        "Плашка сверху. ЛКМ по ней открывает карту мира."); y = y - 25
    Check(c, L, y, "Кнопки зума (+ / -)", "showZoom",
        "Приближение и отдаление местности на карте."); y = y - 25
    Check(c, L, y, "Координаты", "showCoords",
        "Справа внизу. ЛКМ отправляет координаты в поле чата."); y = y - 25
    Check(c, L, y, "Часы", "showClock",
        "Слева внизу. ЛКМ — окно времени Blizzard (будильник и секундомер). ПКМ — переключить серверное/местное время."); y = y - 25
    Check(c, L, y, "Местное время вместо серверного", "clockLocal",
        "Если сервер и ваш компьютер в одном часовом поясе, цифры будут одинаковые — это не ошибка."); y = y - 25
    Check(c, L, y, "Кнопка календаря Blizzard", "showCalendar",
        "Стандартная кнопка календаря. Под ней колонкой строятся почта и очередь БГ."); y = y - 25
    Check(c, L, y, "Кнопки управления (А П И Н)", "showCtrl",
        "А — иконки аддонов, П — переместить, И — информация, Н — настройки."); y = y - 25
    Check(c, L, y, "Зум колесом мыши", "wheelZoom"); y = y - 32

    Header(c, L, y, "Скрытие"); y = y - 24
    Check(c, L, y, "Скрывать в бою", "hideInCombat",
        "Миникарта уходит с экрана на время боя и возвращается после."); y = y - 25
    Check(c, L, y, "Скрывать в подземельях", "hideInInstance",
        "Прячет миникарту в любом инстансе: подземелье, рейд, поле боя, арена."); y = y - 34

    Header(c, L, y, "Размер и положение"); y = y - 30
    Slider(c, L, y, "Размер миникарты", "size", 120, 400, 5, 230); y = y - 44
    Slider(c, L, y, "Масштаб фрейма", "scale", 0.5, 2.0, 0.05, 230, "%.2f"); y = y - 44
    Slider(c, L, y, "Размер шрифта", "fontSize", 8, SM.MAX_FONT, 1, 230); y = y - 44
    Slider(c, L, y, "Затемнение плашек", "barAlpha", 0, 1, 0.05, 230, "%.2f"); y = y - 44
    Slider(c, L, y, "Иконки почты / БГ", "blizzIconScale", 0.6, 1.5, 0.05, 230, "%.2f"); y = y - 44
    Slider(c, L, y, "Поправка серверного времени, ч", "clockOffset", -12, 12, 0.5, 230, "%+.1f"); y = y - 42

    Btn(c, L, y, 150, "Переместить миникарту", function()
        SM:ToggleLock(false)
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
    end)
    Btn(c, L + 160, y, 110, "Сброс позиции", function() SM:ResetPosition() end)
    local leftBottom = y - 40

    ------------------------------------------------------------------
    -- ПРАВАЯ КОЛОНКА
    ------------------------------------------------------------------
    local R = 300
    y = -8

    Header(c, R, y, "Стрелка игрока"); y = y - 24
    Check(c, R, y, "Своя стрелка", "customArrow",
        "Своя стрелка с выбором цвета и размера."); y = y - 25
    Check(c, R, y, "Скрывать стандартную стрелку", "hideBlizzArrow",
        "Гасит движковую стрелку прозрачной текстурой. Если на вашем клиенте не сработало — просто не уменьшайте размер ниже 24."); y = y - 30

    local styleBtn = Btn(c, R, y, 250, "", function() end)
    local function RefreshStyle()
        local st = SM.arrowStyles[SM.db.arrowStyle] or SM.arrowStyles[1]
        styleBtn:SetText("Стиль: " .. st.name ..
            " (" .. SM.db.arrowStyle .. "/" .. #SM.arrowStyles .. ")")
    end
    styleBtn:SetScript("OnClick", function()
        SM.db.arrowStyle = SM.db.arrowStyle + 1
        if SM.db.arrowStyle > #SM.arrowStyles then SM.db.arrowStyle = 1 end
        SM.db.arrowTex = nil
        RefreshStyle()
        SM:UpdateAll()
    end)
    RefreshStyle()
    table.insert(refreshers, RefreshStyle)
    y = y - 32

    Slider(c, R, y, "Размер стрелки", "arrowSize", SM.MIN_ARROW, 64, 1, 230); y = y - 44
    ColorSwatch(c, R, y, "Цвет стрелки", "arrowR", "arrowG", "arrowB"); y = y - 28
    ColorSwatch(c, R, y, "Цвет обводки", "borderR", "borderG", "borderB"); y = y - 36

    Header(c, R, y, "Иконки аддонов"); y = y - 24
    Check(c, R, y, "Собирать иконки в панель", "collect",
        "Иконки аддонов складываются в отдельную панель. Открывается кнопкой «А»."); y = y - 30

    local dirBtn = Btn(c, R, y, 250, "", function() end)
    local function RefreshDir()
        local d = SM.barDirs[SM.db.barDir] or SM.barDirs[1]
        dirBtn:SetText("Открывать список: " .. d.name)
    end
    dirBtn:SetScript("OnClick", function()
        SM.db.barDir = SM.db.barDir + 1
        if SM.db.barDir > #SM.barDirs then SM.db.barDir = 1 end
        RefreshDir()
        SM:LayoutIconBar()
    end)
    RefreshDir()
    table.insert(refreshers, RefreshDir)
    y = y - 32

    Slider(c, R, y, "Размер иконок", "buttonSize", 16, 40, 1, 230); y = y - 42

    Btn(c, R, y, 160, "Пересканировать иконки", function()
        local n = SM:CollectButtons() or 0
        SM:Print("Найдено новых иконок: " .. n .. ", всего: " .. #SM.collected)
    end)
    y = y - 40

    Header(c, R, y, "Сброс и диагностика"); y = y - 28

    Btn(c, R, y, 250, "Сбросить ВСЕ настройки на стандартные", ResetAll)
    y = y - 32

    local hint = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", R + 6, y)
    hint:SetWidth(255); hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888Если на карте виден лишний элемент — нажмите кнопку ниже, найдите его имя в чате и выполните /smm hide ИмяФрейма|r")
    y = y - 42

    Btn(c, R, y, 250, "Показать всё, что есть на миникарте", function()
        SM:Dump()
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
    end)
    y = y - 40

    ------------------------------------------------------------------
    -- Высота содержимого считается по факту, ничего не обрежется
    ------------------------------------------------------------------
    c:SetHeight(math.max(-leftBottom, -y) + 20)

    SM.RefreshConfig = function() RefreshAll() end
    p.refresh = RefreshAll   -- при каждом открытии панели
    p.default = ResetAll     -- кнопка «По умолчанию» самого интерфейса

    InterfaceOptions_AddCategory(p)
end
