--[[-------------------------------------------------------------------------
    Ebonhold Checkpoints
    Fenetre de teleportation rapide vers les checkpoints debloques.

    S'appuie sur l'addon serveur ProjectEbonhold :
      ProjectEbonhold.CheckpointService.GetCheckpoints()  -> liste { name, unlocked,
          factionAllowed, kind, serverMapId, id, ... }
      ProjectEbonhold.CheckpointService.UseCheckpoint(id)  -> teleporte (meme appel
          que le clic sur le pin de la carte du monde).

    Fonctions :
      - Liste filtrable : recherche + onglets continents + onglets type (vol/donjon/raid).
      - Favoris (etoile par destination, section "Favoris" + filtre "favoris seulement").
      - Mode reduit : minimise la fenetre pour n'afficher que les favoris.
      - Fenetre redimensionnable (poignee en bas a droite).
      - Bilingue FR / EN (interface + noms de lieux) avec bouton de bascule.
        Les noms FR sont dans EbonholdCheckpoints_Names.lua (extraits du client frFR).

    La liste arrive du serveur de facon asynchrone (evenement SEND_CHECKPOINTS_DATA) :
    ProjectEbonhold reconstruit alors une NOUVELLE table puis appelle
    ProjectEbonhold.CheckpointUI.RefreshPins(). On observe cet appel (post-hook) pour
    rafraichir la fenetre des que la reponse est la, avec un repli temporise.
---------------------------------------------------------------------------]]

local ADDON_NAME = ...

local EC = {}
_G.EbonholdCheckpoints = EC

-- Preferences par defaut (SavedVariables)
local DEFAULTS = {
    lang         = "fr",
    showLocked   = false,
    favOnly      = false,
    continent    = "ALL",
    typeFilter   = "ALL",
    sortMode     = "type",
    minimapAngle = 205,
    hideMinimap  = false,
    favorites    = {},   -- [checkpointId] = true
    compact      = false,
    point        = nil,  -- position de la fenetre
    width        = 384,
    height       = 520,
    compactW     = 240,
    compactH     = 190,
}

--==========================================================================
-- Localisation
--==========================================================================

local LOCALE = {
    fr = {
        title = "Checkpoints",
        favoritesSection = "Favoris",
        flight = "Points de vol", dungeons = "Donjons", raids = "Raids",
        search = "Rechercher...",
        lockedLabel = "Verrouilles", lockedTip = "Afficher aussi les checkpoints verrouilles",
        favLabel = "Favoris", favTip = "Afficher uniquement les favoris",
        footer = "%d checkpoints debloques",
        compactEmpty = "Aucun favori.\nClique l'etoile d'une destination pour l'epingler.",
        travel = "Clic pour se teleporter.",
        lockedRow = "Verrouille - a debloquer en jeu.",
        addFav = "Ajouter aux favoris", removeFav = "Retirer des favoris",
        expand = "Agrandir", minimize = "Reduire (favoris seulement)",
        mmTitle = "Ebonhold Checkpoints",
        mmClick = "Clic : ouvrir la liste de teleportation",
        mmDrag = "Glisser : deplacer le bouton",
        langTip = "Passer en anglais", langNext = "EN",
        sortLabel = "Tri", sortType = "Type", sortName = "Nom (A-Z)", sortContinent = "Region",
        allDest = "Destinations", other = "Autre",
        c_all = "Tous", c_ek = "Est", c_kal = "Kalimdor", c_out = "Outreterre", c_north = "Norfendre",
        t_all = "Tous", t_flight = "Vol", t_dungeons = "Donjons", t_raids = "Raids",
        noService = "Service de checkpoints introuvable.\n\nL'addon ProjectEbonhold est absent, desactive ou incompatible avec cette version. Verifie qu'il est active, puis tape /reload.",
    },
    en = {
        title = "Checkpoints",
        favoritesSection = "Favorites",
        flight = "Flight Points", dungeons = "Dungeons", raids = "Raids",
        search = "Search...",
        lockedLabel = "Locked", lockedTip = "Also show locked checkpoints",
        favLabel = "Favorites", favTip = "Show favorites only",
        footer = "%d unlocked checkpoints",
        compactEmpty = "No favorites.\nClick a destination's star to pin it.",
        travel = "Click to travel here.",
        lockedRow = "Locked - unlock it in-game.",
        addFav = "Add to favorites", removeFav = "Remove from favorites",
        expand = "Expand", minimize = "Minimize (favorites only)",
        mmTitle = "Ebonhold Checkpoints",
        mmClick = "Click: open the teleport list",
        mmDrag = "Drag: move the button",
        langTip = "Switch to French", langNext = "FR",
        sortLabel = "Sort", sortType = "Type", sortName = "Name (A-Z)", sortContinent = "Region",
        allDest = "Destinations", other = "Other",
        c_all = "All", c_ek = "EK", c_kal = "Kalimdor", c_out = "Outland", c_north = "Northrend",
        t_all = "All", t_flight = "Flight", t_dungeons = "Dungeons", t_raids = "Raids",
        noService = "Checkpoint service not found.\n\nThe ProjectEbonhold addon is missing, disabled or incompatible with this version. Make sure it is enabled, then type /reload.",
    },
}

function EC:L(key)
    return (LOCALE[self.db.lang] or LOCALE.fr)[key]
end

-- serverMapId -> nom de continent (pour le tooltip)
local CONTINENT_NAMES = {
    fr = { [0] = "Royaumes de l'Est", [1] = "Kalimdor", [30] = "Vallee d'Alterac",
           [530] = "Outreterre", [571] = "Norfendre", [603] = "Ulduar" },
    en = { [0] = "Eastern Kingdoms", [1] = "Kalimdor", [30] = "Alterac Valley",
           [530] = "Outland", [571] = "Northrend", [603] = "Ulduar" },
}

-- Traduit un nom de checkpoint token par token (FR uniquement).
function EC:LocalizeName(name)
    if not name then return "" end
    if self.db.lang ~= "fr" then return name end
    local map = _G.EbonholdCheckpointsNames
    if not map then return name end
    local parts = {}
    for token in string.gmatch(name, "[^,]+") do
        token = token:gsub("^%s+", ""):gsub("%s+$", "")
        parts[#parts + 1] = map[token] or token
    end
    return table.concat(parts, ", ")
end

-- Onglets de filtre par continent
local CONTINENT_TABS = {
    { key = "ALL", lkey = "c_all" },
    { key = 0,     lkey = "c_ek" },
    { key = 1,     lkey = "c_kal" },
    { key = 530,   lkey = "c_out" },
    { key = 571,   lkey = "c_north" },
}

-- Categories connues. "OTHER" recoit tout type que l'addon ne connait pas encore
-- (nouveau kind ajoute plus tard cote serveur) au lieu de provoquer une erreur.
local TYPE_LKEY = { FLIGHT = "flight", MEETINGSTONE = "dungeons", MEETINGSTONE_RAID = "raids", OTHER = "other" }
local TYPE_ORDER = { "FLIGHT", "MEETINGSTONE", "MEETINGSTONE_RAID", "OTHER" }
local TYPE_INDEX = { FLIGHT = 1, MEETINGSTONE = 2, MEETINGSTONE_RAID = 3, OTHER = 4 }

-- kind du checkpoint -> categorie. kind nil = point de vol classique ;
-- kind inconnu = "OTHER".
local function KindKey(kind)
    if kind == nil then return "FLIGHT" end
    if TYPE_INDEX[kind] then return kind end
    return "OTHER"
end

-- Nom de tri (une entree sans nom ne doit pas faire planter table.sort).
local function NameOf(cp)
    return cp.name or ""
end

-- Tri par type (vol, donjons, raids, autre) puis par nom.
local function SortByTypeThenName(a, b)
    local ka, kb = KindKey(a.kind), KindKey(b.kind)
    if ka ~= kb then return TYPE_INDEX[ka] < TYPE_INDEX[kb] end
    return NameOf(a) < NameOf(b)
end

local function SortByName(a, b)
    return NameOf(a) < NameOf(b)
end

local function SortByContinentThenName(a, b)
    local ca, cb = a.serverMapId or 0, b.serverMapId or 0
    if ca ~= cb then return ca < cb end
    return NameOf(a) < NameOf(b)
end

local function GetComparator(mode)
    if mode == "name" then return SortByName
    elseif mode == "continent" then return SortByContinentThenName
    else return SortByTypeThenName end
end

-- Modes de tri proposes dans le menu
local SORT_MODES = {
    { key = "type",      lkey = "sortType" },
    { key = "name",      lkey = "sortName" },
    { key = "continent", lkey = "sortContinent" },
}

-- Onglets de filtre par type
local TYPE_TABS = {
    { key = "ALL",               lkey = "t_all" },
    { key = "FLIGHT",            lkey = "t_flight" },
    { key = "MEETINGSTONE",      lkey = "t_dungeons" },
    { key = "MEETINGSTONE_RAID", lkey = "t_raids" },
}

-- tex = chemin texture ; coord = {l,r,t,b} optionnel (sous-region d'une planche).
local TYPE_ICON = {
    FLIGHT            = { tex = "Interface\\Minimap\\Tracking\\FlightMaster" },
    MEETINGSTONE      = { tex = "Interface\\LFGFrame\\LFG-Eye", coord = { 0, 0.125, 0, 0.25 } },
    MEETINGSTONE_RAID = { tex = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    OTHER             = { tex = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

local function ApplyTypeIcon(tex, kind)
    local info = TYPE_ICON[KindKey(kind)] or TYPE_ICON.FLIGHT
    tex:SetTexture(info.tex)
    if info.coord then
        tex:SetTexCoord(info.coord[1], info.coord[2], info.coord[3], info.coord[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-- Etoile jaune des marqueurs de raid : texture standard, toujours presente.
local STAR_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local ROW_HEIGHT = 24
local FRAME_W    = 384
local FRAME_H    = 520
local MIN_W, MIN_H = 340, 320
local MAX_W, MAX_H = 600, 820
local COMPACT_W  = 240
local LIST_TOP   = -130
local LIST_BOTTOM = 46

--==========================================================================
-- Acces au service serveur
--==========================================================================

local function SetShown(obj, show)
    if show then obj:Show() else obj:Hide() end
end

local function GetService()
    return ProjectEbonhold and ProjectEbonhold.CheckpointService
end

-- Vrai si le service serveur expose bien la liste des checkpoints.
local function HasService()
    local svc = GetService()
    return type(svc) == "table" and type(svc.GetCheckpoints) == "function"
end

local function Normalize(s)
    if not s then return "" end
    return string.lower(s):gsub("%s+", " ")
end

local function IsFavorite(id)
    return EC.db and EC.db.favorites[id] == true
end

local function ToggleFavorite(id)
    if not EC.db then return end
    if EC.db.favorites[id] then
        EC.db.favorites[id] = nil
    else
        EC.db.favorites[id] = true
    end
end

local function GetUniqueCheckpoints()
    local out = {}
    if not HasService() then return out end
    local list = GetService().GetCheckpoints()
    if type(list) ~= "table" then return out end
    local seen = {}
    for _, cp in ipairs(list) do
        if type(cp) == "table" and cp.id ~= nil and cp.factionAllowed ~= false and not seen[cp.id] then
            seen[cp.id] = true
            table.insert(out, cp)
        end
    end
    return out
end

-- Reponse du serveur : ProjectEbonhold remplace la table renvoyee par
-- GetCheckpoints() a chaque reception (SEND_CHECKPOINTS_DATA) puis appelle
-- CheckpointUI.RefreshPins(). RefreshPins est aussi appele a chaque mise a jour
-- de la carte : on ne rafraichit donc que si la table a change.
function EC:OnServerData()
    self.awaitingData = false
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

function EC:InstallDataHook()
    if self.dataHooked or not hooksecurefunc then return end
    local ui = ProjectEbonhold and ProjectEbonhold.CheckpointUI
    if type(ui) ~= "table" or type(ui.RefreshPins) ~= "function" then return end
    self.dataHooked = true
    if HasService() then self.lastList = GetService().GetCheckpoints() end
    -- Post-hook : l'original s'execute normalement, on observe seulement.
    hooksecurefunc(ui, "RefreshPins", function()
        if not HasService() then return end
        local list = GetService().GetCheckpoints()
        if list == EC.lastList then return end
        EC.lastList = list
        -- Le rafraichissement est differe d'une image pour rester hors du
        -- traitement de l'evenement serveur.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() EC:OnServerData() end)
        else
            EC:OnServerData()
        end
    end)
end

-- Demande la liste au serveur. Le rafraichissement se fait a la reponse (hook
-- ci-dessus) ; repli temporise si la reponse n'est pas detectee (hook absent,
-- serveur lent).
function EC:RequestData()
    local svc = GetService()
    if not (svc and type(svc.RequestCheckpoints) == "function") then return end
    self:InstallDataHook()
    -- Seule une table differente de l'actuelle signalera la reponse.
    if HasService() then self.lastList = svc.GetCheckpoints() end
    self.awaitingData = true
    svc.RequestCheckpoints()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function()
            if EC.awaitingData then EC:Refresh() end
        end)
        C_Timer.After(2.0, function()
            if EC.awaitingData then EC:OnServerData() end
        end)
    end
end

--==========================================================================
-- Teleportation
--==========================================================================

local function Teleport(cp)
    local svc = GetService()
    if not (cp and cp.unlocked) then return end
    if svc and svc.UseCheckpoint then
        svc.UseCheckpoint(cp.id)
        if EC.db.compact then
            -- Une teleportation entre zones declenche un ecran de chargement qui
            -- masque (voire reinitialise) la fenetre : on memorise l'intention
            -- de reouverture et on reessaie apres le chargement.
            EC.db.pendingReopen = true
            EC:ScheduleReopen()
        elseif EC.frame then
            EC.frame:Hide()
        end
    end
end

--==========================================================================
-- Construction de la liste (mode complet)
--==========================================================================

-- Lignes : { header=true, lkey=<cle locale>, count=N } ou { cp=<checkpoint> }.
function EC:BuildRows()
    local rows = {}
    local search = Normalize(self.search)
    local continent = self.db.continent
    local typeFilter = self.db.typeFilter
    local showLocked = self.db.showLocked
    local favOnly = self.db.favOnly

    local mode = self.db.sortMode or "type"
    local cmp = GetComparator(mode)

    local unlockedCount = 0
    local favs = {}
    local others = {}

    for _, cp in ipairs(GetUniqueCheckpoints()) do
        if cp.unlocked then unlockedCount = unlockedCount + 1 end

        local k = KindKey(cp.kind)
        -- la recherche porte sur le nom anglais ET le nom localise
        local passSearch = (search == "")
            or string.find(Normalize(cp.name), search, 1, true) ~= nil
            or string.find(Normalize(self:LocalizeName(cp.name)), search, 1, true) ~= nil
        local passType = (typeFilter == "ALL") or (k == typeFilter)
        local passContinent = (continent == "ALL") or (cp.serverMapId == continent)

        if IsFavorite(cp.id) and cp.unlocked and passSearch and passType and passContinent then
            table.insert(favs, cp)
        elseif not favOnly then
            local passLocked = cp.unlocked or showLocked
            if passContinent and passLocked and passSearch and passType then
                table.insert(others, cp)
            end
        end
    end

    local function addSection(label, list)
        table.insert(rows, { header = true, label = label, count = #list })
        for _, cp in ipairs(list) do rows[#rows + 1] = { cp = cp } end
    end

    if #favs > 0 then
        table.sort(favs, cmp)
        addSection(self:L("favoritesSection"), favs)
    end

    if #others > 0 then
        if mode == "name" then
            table.sort(others, SortByName)
            addSection(self:L("allDest"), others)
        elseif mode == "continent" then
            local groups, order = {}, {}
            for _, cp in ipairs(others) do
                local id = cp.serverMapId or -1
                if not groups[id] then groups[id] = {}; order[#order + 1] = id end
                table.insert(groups[id], cp)
            end
            table.sort(order)
            for _, id in ipairs(order) do
                table.sort(groups[id], SortByName)
                addSection(CONTINENT_NAMES[self.db.lang][id] or self:L("other"), groups[id])
            end
        else -- type
            local buckets = {}
            for _, k in ipairs(TYPE_ORDER) do buckets[k] = {} end
            for _, cp in ipairs(others) do table.insert(buckets[KindKey(cp.kind)], cp) end
            for _, k in ipairs(TYPE_ORDER) do
                if #buckets[k] > 0 then
                    table.sort(buckets[k], SortByName)
                    addSection(self:L(TYPE_LKEY[k]), buckets[k])
                end
            end
        end
    end

    return rows, unlockedCount
end

local function UpdateStarVisual(star, isFav)
    if isFav then
        star.tex:SetDesaturated(false)
        star.tex:SetVertexColor(1, 1, 1)
        star.tex:SetAlpha(1)
    else
        star.tex:SetDesaturated(true)
        star.tex:SetVertexColor(0.8, 0.8, 0.8)
        star.tex:SetAlpha(0.40)
    end
end

function EC:VisibleRowCount()
    local h = self.scroll:GetHeight()
    if h <= 0 then h = self.listBG:GetHeight() - 8 end
    return math.max(1, math.floor((h - 4) / ROW_HEIGHT))
end

function EC:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    if self.db.compact then self:RefreshCompact() return end

    local rows, unlockedCount = self:BuildRows()
    self.rows = rows

    local numRows = self:VisibleRowCount()
    self:EnsureRows(numRows)

    FauxScrollFrame_Update(self.scroll, #rows, numRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(self.scroll)

    for i = 1, #self.rowButtons do
        local btn = self.rowButtons[i]
        local data = (i <= numRows) and rows[i + offset] or nil
        if data then
            if data.header then
                btn.cp = nil
                btn.icon:Hide()
                btn.star:Hide()
                btn.text:SetText(data.label .. "  (" .. data.count .. ")")
                btn.text:SetPoint("LEFT", btn, "LEFT", 6, 0)
                btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                btn.text:SetTextColor(1, 0.82, 0)
                btn:EnableMouse(false)
                btn.highlight:SetAlpha(0)
            else
                local cp = data.cp
                btn.cp = cp
                btn.icon:Show()
                ApplyTypeIcon(btn.icon, cp.kind)
                btn.text:SetText(self:LocalizeName(cp.name))
                btn.text:SetPoint("LEFT", btn, "LEFT", 26, 0)
                btn.text:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
                btn:EnableMouse(true)
                if cp.unlocked then
                    btn.text:SetTextColor(1, 1, 1)
                    btn.icon:SetDesaturated(false)
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.highlight:SetAlpha(0.30)
                    btn.star:Show()
                    btn.star.id = cp.id
                    UpdateStarVisual(btn.star, IsFavorite(cp.id))
                else
                    btn.text:SetTextColor(0.45, 0.45, 0.45)
                    btn.icon:SetDesaturated(true)
                    btn.icon:SetVertexColor(0.5, 0.5, 0.5)
                    btn.highlight:SetAlpha(0)
                    btn.star:Hide()
                end
            end
            btn:Show()
        else
            btn.cp = nil
            btn:Hide()
        end
    end

    -- Service serveur absent : message explicite plutot qu'une liste vide.
    local svcOK = HasService()
    SetShown(self.listMsg, not svcOK)
    if svcOK then
        self.footer:SetText(string.format(self:L("footer"), unlockedCount))
    else
        self.listMsg:SetText(self:L("noService"))
        self.footer:SetText("")
    end
end

--==========================================================================
-- Mode reduit (favoris uniquement)
--==========================================================================

local function GetUnlockedFavorites()
    local favs = {}
    for _, cp in ipairs(GetUniqueCheckpoints()) do
        if cp.unlocked and IsFavorite(cp.id) then
            table.insert(favs, cp)
        end
    end
    table.sort(favs, SortByTypeThenName)
    return favs
end

function EC:GetCompactRow(i)
    local b = self.compactRows[i]
    if b then return b end

    b = CreateFrame("Button", nil, self.compactFrame)
    b:SetHeight(ROW_HEIGHT)
    -- la position et la largeur sont definies par RefreshCompact (grille).

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.icon = icon

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", b, "LEFT", 26, 0)
    text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    b.text = text

    b:SetScript("OnClick", function(self) if self.cp then Teleport(self.cp) end end)
    b:SetScript("OnEnter", function(self)
        if not self.cp then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EC:LocalizeName(self.cp.name), 1, 0.82, 0)
        GameTooltip:AddLine(EC:L("travel"), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.compactRows[i] = b
    return b
end

local COMPACT_CELL_W = 150  -- largeur mini d'une colonne de favori

function EC:RefreshCompact()
    local favs = GetUnlockedFavorites()
    local n = #favs

    local availW = self.compactFrame:GetWidth()
    if availW <= 0 then availW = (self.db.compactW or COMPACT_W) - 24 end

    -- Le nombre de colonnes depend de la LARGEUR choisie par l'utilisateur ;
    -- la hauteur de la fenetre s'ajuste ensuite pour tout contenir.
    local maxCols = math.max(1, math.floor(availW / COMPACT_CELL_W))
    local cols = math.max(1, math.min(maxCols, math.max(n, 1)))
    local cellW = availW / cols

    for i, cp in ipairs(favs) do
        local b = self:GetCompactRow(i)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.compactFrame, "TOPLEFT", col * cellW, -row * ROW_HEIGHT)
        b:SetWidth(cellW - 4)
        b.cp = cp
        ApplyTypeIcon(b.icon, cp.kind)
        b.text:SetText(self:LocalizeName(cp.name))
        b:Show()
    end
    for i = n + 1, #self.compactRows do
        self.compactRows[i]:Hide()
    end
    -- Liste vide : "aucun favori", ou message d'erreur si le service manque.
    if n == 0 then
        self.compactEmpty:SetWidth(math.max(60, availW - 8))
        self.compactEmpty:SetText(HasService() and self:L("compactEmpty") or self:L("noService"))
    end
    SetShown(self.compactEmpty, n == 0)

    -- Hauteur auto = juste ce qu'il faut pour contenir toutes les lignes.
    local usedRows = math.max(1, math.ceil(math.max(n, 1) / cols))
    local h = 34 + usedRows * ROW_HEIGHT + 12
    if n == 0 then
        h = math.max(h, 34 + 6 + self.compactEmpty:GetStringHeight() + 12)
    end
    if h > MAX_H then h = MAX_H end
    if math.abs(self.frame:GetHeight() - h) > 0.5 then
        self.frame:SetHeight(h)
    end
end

--==========================================================================
-- Bascule complet / reduit + langue
--==========================================================================

function EC:SetFullWidgetsShown(show)
    for _, t in ipairs(self.contTabs) do SetShown(t, show) end
    for _, t in ipairs(self.typeTabs) do SetShown(t, show) end
    for _, w in ipairs({ self.searchBox, self.clearBtn, self.sortBtn, self.listBG, self.lockedCheck, self.favCheck, self.footer, self.resizeGrip }) do
        SetShown(w, show)
    end
    if not show then self.sortMenu:Hide() end
    if show and self.searchBox:GetText() == "" then
        self.searchHint:Show()
    else
        self.searchHint:Hide()
    end
end

function EC:UpdateSortLabel()
    local lkey = "sortType"
    for _, m in ipairs(SORT_MODES) do
        if m.key == self.db.sortMode then lkey = m.lkey end
    end
    self.sortBtn.text:SetText(self:L(lkey))
    self.sortBtn:SetWidth(self.sortBtn.text:GetStringWidth() + 18)
end

function EC:UpdateSortMenuTexts()
    local maxw = 90
    for _, opt in ipairs(self.sortOptions) do
        opt.text:SetText(self:L(opt.lkey))
        if opt.modeKey == self.db.sortMode then
            opt.text:SetTextColor(1, 0.82, 0)
        else
            opt.text:SetTextColor(1, 1, 1)
        end
        maxw = math.max(maxw, opt.text:GetStringWidth() + 24)
    end
    self.sortMenu:SetWidth(maxw)
end

function EC:UpdateLocaleTexts()
    self.searchHint:SetText(self:L("search"))
    _G[self.lockedCheck:GetName() .. "Text"]:SetText(self:L("lockedLabel"))
    _G[self.favCheck:GetName() .. "Text"]:SetText(self:L("favLabel"))
    self.compactEmpty:SetText(self:L("compactEmpty"))
    self.langBtn.text:SetText(self:L("langNext"))
    for _, tab in ipairs(self.contTabs) do
        tab.text:SetText(self:L(tab.lkey))
        tab:SetWidth(tab.text:GetStringWidth() + 16)
    end
    for _, tab in ipairs(self.typeTabs) do
        tab.text:SetText(self:L(tab.lkey))
        tab:SetWidth(tab.text:GetStringWidth() + 16)
    end
    self:UpdateSortLabel()
end

function EC:SetLanguage(lang)
    self.db.lang = lang
    self:UpdateLocaleTexts()
    self:ApplyMode()
end

function EC:ApplyMode()
    local compact = self.db.compact
    if compact then
        self:SetFullWidgetsShown(false)
        self.compactFrame:Show()
        self.resizeGrip:Show()
        self.title:SetText(self:L("favoritesSection"))
        self.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
        self.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Down")
        self.frame:SetMinResize(150, 64)
        self.frame:SetSize(self.db.compactW or COMPACT_W, self.db.compactH or 190)
        self:RefreshCompact()
    else
        self:SetFullWidgetsShown(true)
        self.compactFrame:Hide()
        self.title:SetText(self:L("title"))
        self.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
        self.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
        self.frame:SetMinResize(MIN_W, MIN_H)
        self.frame:SetSize(self.db.width or FRAME_W, self.db.height or FRAME_H)
        self.lockedCheck:SetChecked(self.db.showLocked)
        self.favCheck:SetChecked(self.db.favOnly)
        self:UpdateTabs()
        self:Refresh()
    end
end

--==========================================================================
-- Construction de l'interface
--==========================================================================

local function MakeFilterTab(parent, info, group)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(20)
    tab.key = info.key
    tab.lkey = info.lkey
    tab.group = group

    local fs = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    tab.text = fs

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.15, 0.15, 0.15, 0.8)
    tab.bg = bg

    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(1, 1, 1, 0.12)

    tab:SetScript("OnClick", function(self)
        if EC.searchBox then EC.searchBox:ClearFocus() end
        if self.group == "continent" then
            EC.db.continent = self.key
        else
            EC.db.typeFilter = self.key
        end
        EC:UpdateTabs()
        EC:Refresh()
    end)
    return tab
end

function EC:UpdateTabs()
    local function style(tab, active)
        if active then
            tab.bg:SetTexture(0.20, 0.40, 0.65, 0.95)
            tab.text:SetTextColor(1, 1, 1)
        else
            tab.bg:SetTexture(0.15, 0.15, 0.15, 0.8)
            tab.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
    for _, tab in ipairs(self.contTabs) do style(tab, tab.key == self.db.continent) end
    for _, tab in ipairs(self.typeTabs) do style(tab, tab.key == self.db.typeFilter) end
end

local function MakeStar(parent)
    local star = CreateFrame("Button", nil, parent)
    star:SetSize(16, 16)
    star:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    star:SetFrameLevel(parent:GetFrameLevel() + 2)

    local tex = star:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(STAR_TEXTURE)
    star.tex = tex

    star:SetScript("OnClick", function(self)
        if not self.id then return end
        ToggleFavorite(self.id)
        EC:Refresh()
    end)
    star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(IsFavorite(self.id) and EC:L("removeFav") or EC:L("addFav"), 1, 1, 1)
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return star
end

function EC:CreateRow(i)
    local scroll = self.scroll
    local btn = CreateFrame("Button", nil, self.listBG)
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
    text:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
    text:SetJustifyH("LEFT")
    btn.text = text

    btn.star = MakeStar(btn)

    btn:SetScript("OnClick", function(self)
        if self.cp and self.cp.unlocked then Teleport(self.cp) end
    end)
    btn:SetScript("OnEnter", function(self)
        if not self.cp then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EC:LocalizeName(self.cp.name), 1, 0.82, 0)
        local cont = CONTINENT_NAMES[EC.db.lang][self.cp.serverMapId]
        if cont then GameTooltip:AddLine(cont, 0.7, 0.7, 0.7) end
        if self.cp.unlocked then
            GameTooltip:AddLine(EC:L("travel"), 0.4, 1, 0.4)
        else
            GameTooltip:AddLine(EC:L("lockedRow"), 1, 0.35, 0.35)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.rowButtons[i] = btn
    return btn
end

function EC:EnsureRows(n)
    for i = #self.rowButtons + 1, n do
        self:CreateRow(i)
    end
end

function EC:BuildUI()
    if self.frame then return end

    local f = CreateFrame("Frame", "EbonholdCheckpointsFrame", UIParent)
    f:SetSize(self.db.width or FRAME_W, self.db.height or FRAME_H)
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
    f:SetResizable(true)
    f:SetMinResize(MIN_W, MIN_H)
    f:SetMaxResize(MAX_W, MAX_H)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        EC.db.point = { point, relPoint, x, y }
    end)
    f:SetScript("OnSizeChanged", function(self)
        if not EC.db then return end
        if EC.db.compact then
            EC.db.compactW = self:GetWidth()
            EC.db.compactH = self:GetHeight()
            EC:RefreshCompact()
        else
            EC.db.width = self:GetWidth()
            EC.db.height = self:GetHeight()
            EC:Refresh()
        end
    end)
    f:SetScript("OnMouseDown", function()
        if EC.searchBox then EC.searchBox:ClearFocus() end
        if EC.sortMenu then EC.sortMenu:Hide() end
    end)
    f:SetScript("OnShow", function() EC:OnShow() end)
    f:Hide()
    tinsert(UISpecialFrames, "EbonholdCheckpointsFrame")
    self.frame = f

    -- Capteur de clic plein ecran (sous la fenetre) : un clic en dehors de la
    -- zone de texte fait perdre le focus a la recherche.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("MEDIUM")
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", function()
        if EC.searchBox then EC.searchBox:ClearFocus() end
    end)
    self.focusCatcher = catcher

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    self.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    -- Fermeture volontaire : annule une eventuelle reouverture auto en attente.
    close:HookScript("OnClick", function() if EC.db then EC.db.pendingReopen = false end end)

    -- Bouton reduire / agrandir
    local minBtn = CreateFrame("Button", nil, f)
    minBtn:SetSize(24, 24)
    minBtn:SetPoint("TOPRIGHT", -30, -8)
    minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
    minBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    minBtn:SetScript("OnClick", function()
        EC.db.compact = not EC.db.compact
        EC:ApplyMode()
    end)
    minBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(EC.db.compact and EC:L("expand") or EC:L("minimize"), 1, 1, 1)
        GameTooltip:Show()
    end)
    minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minBtn = minBtn

    -- Bouton de langue (haut gauche)
    local langBtn = CreateFrame("Button", nil, f)
    langBtn:SetSize(30, 20)
    langBtn:SetPoint("TOPLEFT", 14, -12)
    local lbg = langBtn:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetTexture(0.20, 0.40, 0.65, 0.95)
    local lhl = langBtn:CreateTexture(nil, "HIGHLIGHT")
    lhl:SetAllPoints()
    lhl:SetTexture(1, 1, 1, 0.15)
    local ltext = langBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ltext:SetPoint("CENTER")
    ltext:SetTextColor(1, 1, 1)
    langBtn.text = ltext
    langBtn:SetScript("OnClick", function()
        EC:SetLanguage(EC.db.lang == "fr" and "en" or "fr")
    end)
    langBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EC:L("langTip"), 1, 1, 1)
        GameTooltip:Show()
    end)
    langBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.langBtn = langBtn

    -- Rangee 1 : continents
    self.contTabs = {}
    local prev
    for i, info in ipairs(CONTINENT_TABS) do
        local tab = MakeFilterTab(f, info, "continent")
        if i == 1 then tab:SetPoint("TOPLEFT", 16, -42)
        else tab:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        prev = tab
        self.contTabs[i] = tab
    end

    -- Rangee 2 : type
    self.typeTabs = {}
    prev = nil
    for i, info in ipairs(TYPE_TABS) do
        local tab = MakeFilterTab(f, info, "type")
        if i == 1 then tab:SetPoint("TOPLEFT", 16, -66)
        else tab:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        prev = tab
        self.typeTabs[i] = tab
    end

    -- Menu de tri (rangee 2, a droite)
    local sortBtn = CreateFrame("Button", nil, f)
    sortBtn:SetHeight(20)
    sortBtn:SetPoint("TOPRIGHT", -14, -66)
    local sbg = sortBtn:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetTexture(0.18, 0.18, 0.22, 0.9)
    local shl = sortBtn:CreateTexture(nil, "HIGHLIGHT")
    shl:SetAllPoints()
    shl:SetTexture(1, 1, 1, 0.12)
    local stext = sortBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stext:SetPoint("CENTER")
    sortBtn.text = stext
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(EC:L("sortLabel"), 1, 1, 1)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.sortBtn = sortBtn

    local menu = CreateFrame("Frame", nil, f)
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    menu:SetPoint("TOPRIGHT", sortBtn, "BOTTOMRIGHT", 0, -2)
    menu:Hide()
    local OPTH = 20
    menu:SetSize(110, #SORT_MODES * OPTH + 8)
    self.sortOptions = {}
    for i, m in ipairs(SORT_MODES) do
        local opt = CreateFrame("Button", nil, menu)
        opt:SetHeight(OPTH)
        opt:SetPoint("TOPLEFT", 4, -4 - (i - 1) * OPTH)
        opt:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * OPTH)
        local ot = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ot:SetPoint("LEFT", 6, 0)
        ot:SetJustifyH("LEFT")
        opt.text = ot
        opt.modeKey = m.key
        opt.lkey = m.lkey
        local ohl = opt:CreateTexture(nil, "HIGHLIGHT")
        ohl:SetAllPoints()
        ohl:SetTexture(1, 1, 1, 0.2)
        opt:SetScript("OnClick", function(self)
            EC.db.sortMode = self.modeKey
            EC.sortMenu:Hide()
            EC:UpdateSortLabel()
            EC:Refresh()
        end)
        self.sortOptions[i] = opt
    end
    self.sortMenu = menu

    sortBtn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            EC:UpdateSortMenuTexts()
            menu:Show()
        end
    end)

    -- Bouton croix rouge : vide la recherche
    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetSize(20, 20)
    clearBtn:SetPoint("TOPRIGHT", -20, -97)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    self.clearBtn = clearBtn

    -- Recherche
    local search = CreateFrame("EditBox", "EbonholdCheckpointsSearch", f, "InputBoxTemplate")
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", 22, -98)
    search:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        EC.search = self:GetText()
        EC:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.searchBox = search

    clearBtn:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)

    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", search, "LEFT", 4, 0)
    self.searchHint = searchHint
    search:SetScript("OnEditFocusGained", function()
        searchHint:Hide()
        EC.focusCatcher:Show()
    end)
    search:SetScript("OnEditFocusLost", function(self)
        EC.focusCatcher:Hide()
        if self:GetText() == "" then searchHint:Show() end
    end)

    -- Zone de liste
    local listBG = CreateFrame("Frame", nil, f)
    listBG:SetPoint("TOPLEFT", 16, LIST_TOP)
    listBG:SetPoint("BOTTOMRIGHT", -34, LIST_BOTTOM)
    listBG:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listBG:SetBackdropColor(0, 0, 0, 0.5)
    listBG:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    self.listBG = listBG

    -- Message affiche a la place de la liste si le service serveur manque.
    local listMsg = listBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listMsg:SetPoint("LEFT", listBG, "LEFT", 16, 0)
    listMsg:SetPoint("RIGHT", listBG, "RIGHT", -16, 0)
    listMsg:SetJustifyH("CENTER")
    listMsg:SetTextColor(1, 0.45, 0.35)
    listMsg:Hide()
    self.listMsg = listMsg

    local scroll = CreateFrame("ScrollFrame", "EbonholdCheckpointsScroll", listBG, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() EC:Refresh() end)
    end)
    self.scroll = scroll

    self.rowButtons = {}
    self:EnsureRows(self:VisibleRowCount())

    -- Pied : cases + compteur
    local check = CreateFrame("CheckButton", "EbonholdCheckpointsLocked", f, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("BOTTOMLEFT", 14, 14)
    local checkText = _G[check:GetName() .. "Text"]
    checkText:SetFontObject(GameFontHighlightSmall)
    check:SetScript("OnClick", function(self)
        if EC.searchBox then EC.searchBox:ClearFocus() end
        EC.db.showLocked = self:GetChecked() and true or false
        EC:Refresh()
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EC:L("lockedTip"), 1, 1, 1)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.lockedCheck = check

    local favCheck = CreateFrame("CheckButton", "EbonholdCheckpointsFavOnly", f, "UICheckButtonTemplate")
    favCheck:SetSize(20, 20)
    favCheck:SetPoint("LEFT", checkText, "RIGHT", 10, 0)
    _G[favCheck:GetName() .. "Text"]:SetFontObject(GameFontHighlightSmall)
    favCheck:SetScript("OnClick", function(self)
        if EC.searchBox then EC.searchBox:ClearFocus() end
        EC.db.favOnly = self:GetChecked() and true or false
        EC:Refresh()
    end)
    favCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(EC:L("favTip"), 1, 1, 1)
        GameTooltip:Show()
    end)
    favCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.favCheck = favCheck

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMRIGHT", -24, 20)
    footer:SetJustifyH("RIGHT")
    self.footer = footer

    -- Poignee de redimensionnement
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 7)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        -- En mode reduit, seule la largeur est ajustable (hauteur auto).
        f:StartSizing(EC.db.compact and "RIGHT" or "BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if EC.db.compact then
            EC.db.compactW = f:GetWidth()
            EC.db.compactH = f:GetHeight()
            EC:RefreshCompact()
        else
            EC.db.width = f:GetWidth()
            EC.db.height = f:GetHeight()
            EC:Refresh()
        end
    end)
    self.resizeGrip = grip

    -- Mode reduit
    local compactFrame = CreateFrame("Frame", nil, f)
    compactFrame:SetPoint("TOPLEFT", 12, -34)
    compactFrame:SetPoint("BOTTOMRIGHT", -12, 8)
    compactFrame:Hide()
    self.compactFrame = compactFrame
    self.compactRows = {}

    local empty = compactFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOP", 0, -6)
    empty:SetWidth(COMPACT_W - 28)
    self.compactEmpty = empty

    self:UpdateLocaleTexts()
end

function EC:OnShow()
    self.search = self.searchBox:GetText()
    self:ApplyMode()
    -- Affiche tout de suite la liste connue, puis la rafraichit a la reponse.
    self:RequestData()
end

-- Rouvre effectivement la mini-barre si une reouverture est en attente.
-- L'intention (pendingReopen) est stockee dans les SavedVariables : elle survit
-- donc meme si le changement de continent reinitialise l'addon (comportement
-- "reload" du serveur). On reconstruit l'UI au besoin.
function EC:DoReopen()
    if not (self.db and self.db.pendingReopen) then return end
    if not self.db.compact then
        self.db.pendingReopen = false
        return
    end
    self:BuildUI()
    if self.frame and not self.frame:IsShown() then
        if self.db.point then
            local p = self.db.point
            self.frame:ClearAllPoints()
            self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        self.frame:Show()
    end
end

-- Programme plusieurs tentatives de reouverture apres une teleportation, le
-- temps que l'ecran de chargement se termine (l'UI peut etre masquee tardivement).
function EC:ScheduleReopen()
    if not (C_Timer and C_Timer.After) then
        self:DoReopen()
        return
    end
    for _, d in ipairs({ 0.3, 1.0, 2.0, 3.5 }) do
        C_Timer.After(d, function() EC:DoReopen() end)
    end
    C_Timer.After(5.0, function()
        if EC.db then EC.db.pendingReopen = false end
    end)
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

    local function UpdatePosition()
        local angle = math.rad(EC.db.minimapAngle)
        btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
    end

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
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnClick", function() EC:Toggle() end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(EC:L("mmTitle"), 1, 0.82, 0)
        GameTooltip:AddLine(EC:L("mmClick"), 1, 1, 1)
        GameTooltip:AddLine(EC:L("mmDrag"), 0.7, 0.7, 0.7)
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
        if db[k] == nil then
            db[k] = (type(v) == "table") and {} or v
        end
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
        -- ProjectEbonhold (dependance) est deja charge : on observe ses mises a
        -- jour pour rafraichir aussi une fenetre deja ouverte (ex. nouveau checkpoint).
        EC:InstallDataHook()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if EC.db and EC.db.pendingReopen then
            EC:ScheduleReopen()
        elseif EC.frame and EC.frame:IsShown() then
            EC:Refresh()
        end
    end
end)

SLASH_EBONHOLDCP1 = "/tp"
SLASH_EBONHOLDCP2 = "/cp"
SLASH_EBONHOLDCP3 = "/checkpoint"
SlashCmdList["EBONHOLDCP"] = function() EC:Toggle() end
