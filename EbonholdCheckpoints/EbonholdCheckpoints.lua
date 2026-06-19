--[[-------------------------------------------------------------------------
    Ebonhold Checkpoints
    Fenetre de teleportation rapide vers les checkpoints debloques.

    S'appuie sur l'addon serveur ProjectEbonhold :
      ProjectEbonhold.CheckpointService.GetCheckpoints()  -> liste { name, unlocked,
          factionAllowed, kind, serverMapId, id, ... }
      ProjectEbonhold.CheckpointService.UseCheckpoint(id)  -> teleporte (meme appel
          que le clic sur le pin de la carte du monde).
---------------------------------------------------------------------------]]

local ADDON_NAME = ...

local EC = {}
_G.EbonholdCheckpoints = EC

-- Preferences par defaut (SavedVariables)
local DEFAULTS = {
    showLocked = false,
    continent  = "ALL",
    minimapAngle = 205,
    hideMinimap  = false,
}

-- serverMapId -> nom de continent
local CONTINENT_NAMES = {
    [0]   = "Royaumes de l'Est",
    [1]   = "Kalimdor",
    [30]  = "Vallee d'Alterac",
    [530] = "Outreterre",
    [571] = "Norfendre",
    [603] = "Ulduar",
}

-- Onglets de filtre par continent (les autres serverMapId restent visibles via "Tous")
local CONTINENT_TABS = {
    { key = "ALL", label = "Tous" },
    { key = 0,     label = "Est" },
    { key = 1,     label = "Kalimdor" },
    { key = 530,   label = "Outreterre" },
    { key = 571,   label = "Norfendre" },
}

-- kind du checkpoint -> categorie affichee. kind nil = point de vol classique.
local function KindKey(kind)
    return kind or "FLIGHT"
end

local TYPE_LABELS = {
    FLIGHT           = "Points de vol",
    MEETINGSTONE     = "Donjons",
    MEETINGSTONE_RAID = "Raids",
}
local TYPE_ORDER = { "FLIGHT", "MEETINGSTONE", "MEETINGSTONE_RAID" }

local TYPE_ICON = {
    FLIGHT            = "Interface\\Minimap\\Tracking\\FlightMaster",
    MEETINGSTONE      = "Interface\\Minimap\\Vehicle-AllianceMeetingStone",
    MEETINGSTONE_RAID = "Interface\\Minimap\\Vehicle-AllianceMeetingStone",
}

local ROW_HEIGHT = 24
local NUM_ROWS   = 16
local FRAME_W    = 384

--==========================================================================
-- Acces au service serveur
--==========================================================================

local function GetService()
    return ProjectEbonhold and ProjectEbonhold.CheckpointService
end

local function Normalize(s)
    if not s then return "" end
    return string.lower(s):gsub("%s+", " ")
end

--==========================================================================
-- Construction de la liste affichee
--==========================================================================

-- Renvoie une liste plate de lignes :
--   { header = true, label = "..." }            -> en-tete de section
--   { cp = <checkpoint> }                        -> une destination
-- + le nombre total de destinations et le nombre de destinations debloquees.
function EC:BuildRows()
    local rows = {}
    local svc = GetService()
    if not svc or not svc.GetCheckpoints then
        return rows, 0, 0
    end

    local list = svc.GetCheckpoints()
    if type(list) ~= "table" then
        return rows, 0, 0
    end

    local search = Normalize(self.search)
    local continent = self.db.continent
    local showLocked = self.db.showLocked

    local seen = {}
    local buckets = { FLIGHT = {}, MEETINGSTONE = {}, MEETINGSTONE_RAID = {} }
    local total, unlockedCount = 0, 0

    for _, cp in ipairs(list) do
        if cp.factionAllowed ~= false and not seen[cp.id] then
            seen[cp.id] = true

            local passContinent = (continent == "ALL") or (cp.serverMapId == continent)
            local passLocked = cp.unlocked or showLocked
            local passSearch = (search == "")
                or string.find(Normalize(cp.name), search, 1, true) ~= nil

            if passContinent and passLocked and passSearch then
                table.insert(buckets[KindKey(cp.kind)], cp)
                total = total + 1
            end

            if cp.unlocked then
                unlockedCount = unlockedCount + 1
            end
        end
    end

    for _, k in ipairs(TYPE_ORDER) do
        local bucket = buckets[k]
        if #bucket > 0 then
            table.sort(bucket, function(a, b) return a.name < b.name end)
            table.insert(rows, { header = true, label = TYPE_LABELS[k] .. "  (" .. #bucket .. ")" })
            for _, cp in ipairs(bucket) do
                table.insert(rows, { cp = cp })
            end
        end
    end

    return rows, total, unlockedCount
end

--==========================================================================
-- Teleportation
--==========================================================================

local function Teleport(cp)
    local svc = GetService()
    if not (cp and cp.unlocked) then return end
    if svc and svc.UseCheckpoint then
        svc.UseCheckpoint(cp.id)
        if EC.frame then EC.frame:Hide() end
    end
end

--==========================================================================
-- Rafraichissement de l'affichage
--==========================================================================

function EC:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local rows, total, unlockedCount = self:BuildRows()
    self.rows = rows

    FauxScrollFrame_Update(self.scroll, #rows, NUM_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(self.scroll)

    for i = 1, NUM_ROWS do
        local btn = self.rowButtons[i]
        local data = rows[i + offset]
        if data then
            if data.header then
                btn.cp = nil
                btn.icon:Hide()
                btn.text:SetText(data.label)
                btn.text:SetPoint("LEFT", btn, "LEFT", 6, 0)
                btn.text:SetTextColor(1, 0.82, 0)
                btn:EnableMouse(false)
                btn.highlight:SetAlpha(0)
            else
                local cp = data.cp
                btn.cp = cp
                btn.icon:Show()
                btn.icon:SetTexture(TYPE_ICON[KindKey(cp.kind)])
                btn.text:SetText(cp.name)
                btn.text:SetPoint("LEFT", btn, "LEFT", 26, 0)
                btn:EnableMouse(true)
                if cp.unlocked then
                    btn.text:SetTextColor(1, 1, 1)
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.highlight:SetAlpha(0.30)
                else
                    btn.text:SetTextColor(0.45, 0.45, 0.45)
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.5, 0.5, 0.5)
                    btn.highlight:SetAlpha(0)
                end
            end
            btn:Show()
        else
            btn.cp = nil
            btn:Hide()
        end
    end

    self.footer:SetText(unlockedCount .. " checkpoints debloques")
end

--==========================================================================
-- Construction de l'interface
--==========================================================================

local function MakeTab(parent, info)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(20)
    tab.key = info.key

    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(info.label)
    tab.text = fs
    tab:SetWidth(fs:GetStringWidth() + 18)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.15, 0.15, 0.15, 0.8)
    tab.bg = bg

    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(1, 1, 1, 0.12)

    tab:SetScript("OnClick", function(self)
        EC.db.continent = self.key
        EC:UpdateTabs()
        EC:Refresh()
    end)
    return tab
end

function EC:UpdateTabs()
    for _, tab in ipairs(self.tabs) do
        if tab.key == self.db.continent then
            tab.bg:SetTexture(0.20, 0.40, 0.65, 0.95)
            tab.text:SetTextColor(1, 1, 1)
        else
            tab.bg:SetTexture(0.15, 0.15, 0.15, 0.8)
            tab.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

function EC:BuildUI()
    if self.frame then return end

    local f = CreateFrame("Frame", "EbonholdCheckpointsFrame", UIParent)
    f:SetSize(FRAME_W, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        EC.db.point = { point, relPoint, x, y }
    end)
    f:SetScript("OnShow", function() EC:OnShow() end)
    f:Hide()
    tinsert(UISpecialFrames, "EbonholdCheckpointsFrame") -- fermeture avec Echap
    self.frame = f

    -- Titre
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Checkpoints")

    -- Bouton fermer
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Onglets continents
    self.tabs = {}
    local prev
    for i, info in ipairs(CONTINENT_TABS) do
        local tab = MakeTab(f, info)
        if i == 1 then
            tab:SetPoint("TOPLEFT", 16, -44)
        else
            tab:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        end
        prev = tab
        self.tabs[i] = tab
    end

    -- Barre de recherche
    local search = CreateFrame("EditBox", "EbonholdCheckpointsSearch", f, "InputBoxTemplate")
    search:SetSize(FRAME_W - 56, 22)
    search:SetPoint("TOPLEFT", 22, -74)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        EC.search = self:GetText()
        EC:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.searchBox = search

    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", search, "LEFT", 4, 0)
    searchHint:SetText("Rechercher...")
    search:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then searchHint:Show() end
    end)

    -- Zone de liste (scroll)
    local listBG = CreateFrame("Frame", nil, f)
    listBG:SetPoint("TOPLEFT", 16, -104)
    listBG:SetPoint("BOTTOMRIGHT", -34, 44)
    listBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listBG:SetBackdropColor(0, 0, 0, 0.5)
    listBG:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local scroll = CreateFrame("ScrollFrame", "EbonholdCheckpointsScroll", listBG, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() EC:Refresh() end)
    end)
    self.scroll = scroll

    -- Lignes reutilisables
    self.rowButtons = {}
    for i = 1, NUM_ROWS do
        local btn = CreateFrame("Button", nil, listBG)
        btn:SetHeight(ROW_HEIGHT)
        btn:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        btn:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.3)
        btn.highlight = hl

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
        btn.icon = icon

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", btn, "LEFT", 26, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        btn.text = text

        btn:SetScript("OnClick", function(self)
            if self.cp and self.cp.unlocked then
                Teleport(self.cp)
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if not self.cp then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.cp.name, 1, 0.82, 0)
            local cont = CONTINENT_NAMES[self.cp.serverMapId]
            if cont then GameTooltip:AddLine(cont, 0.7, 0.7, 0.7) end
            if self.cp.unlocked then
                GameTooltip:AddLine("Clic pour se teleporter.", 0.4, 1, 0.4)
            else
                GameTooltip:AddLine("Verrouille - a debloquer en jeu.", 1, 0.35, 0.35)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self.rowButtons[i] = btn
    end

    -- Pied : case "afficher verrouilles" + compteur
    local check = CreateFrame("CheckButton", "EbonholdCheckpointsLocked", f, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("BOTTOMLEFT", 16, 14)
    _G[check:GetName() .. "Text"]:SetText("Afficher les verrouilles")
    check:SetScript("OnClick", function(self)
        EC.db.showLocked = self:GetChecked() and true or false
        EC:Refresh()
    end)
    self.lockedCheck = check

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMRIGHT", -18, 20)
    footer:SetJustifyH("RIGHT")
    self.footer = footer
end

function EC:OnShow()
    self.lockedCheck:SetChecked(self.db.showLocked)
    self:UpdateTabs()

    -- Force une demande de donnees au serveur, puis rafraichit.
    local svc = GetService()
    if svc and svc.RequestCheckpoints then
        svc.RequestCheckpoints()
    end
    self:Refresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function() EC:Refresh() end)
    end
end

function EC:Toggle()
    self:BuildUI()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        if self.db.point then
            local p = self.db.point
            self.frame:ClearAllPoints()
            self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        self.frame:Show()
    end
end

--==========================================================================
-- Bouton minimap
--==========================================================================

function EC:CreateMinimapButton()
    if self.minimapBtn or self.db.hideMinimap then return end

    local btn = CreateFrame("Button", "EbonholdCheckpointsMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    icon:SetPoint("TOPLEFT", 7, -6)
    self.minimapIcon = icon

    local function UpdatePosition()
        local angle = math.rad(EC.db.minimapAngle)
        local x = 80 * math.cos(angle)
        local y = 80 * math.sin(angle)
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    self.UpdateMinimapPosition = UpdatePosition

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            EC.db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnClick", function() EC:Toggle() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ebonhold Checkpoints", 1, 0.82, 0)
        GameTooltip:AddLine("Clic : ouvrir la liste de teleportation", 1, 1, 1)
        GameTooltip:AddLine("Glisser : deplacer le bouton", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapBtn = btn
    UpdatePosition()
end

--==========================================================================
-- Initialisation
--==========================================================================

local function ApplyDefaults(db)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EbonholdCheckpointsDB = ApplyDefaults(EbonholdCheckpointsDB or {})
        EC.db = EbonholdCheckpointsDB
        EC.search = ""
        EC:CreateMinimapButton()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if EC.frame and EC.frame:IsShown() then
            EC:Refresh()
        end
    end
end)

SLASH_EBONHOLDCP1 = "/tp"
SLASH_EBONHOLDCP2 = "/cp"
SLASH_EBONHOLDCP3 = "/checkpoint"
SlashCmdList["EBONHOLDCP"] = function()
    EC:Toggle()
end
