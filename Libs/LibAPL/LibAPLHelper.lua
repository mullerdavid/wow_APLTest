--region LibStub

local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibAPLHelper-1.0", 1

---@class LibAPLHelper-1.0
---@field time number
---@field gcd number
---@field cacheAura table
---@field cacheSpells table
local LibAPLHelper = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibAPLHelper then
    return
end

local LibRangeCheck = LibStub:GetLibrary("LibRangeCheck-3.0")

--endregion

--region WoW API wrappers

---@diagnostic disable-next-line: deprecated
local UnitAura = _G["UnitAura"]
if UnitAura == nil then
    UnitAura = function(unit, i, filter)
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not auraData then
            return nil;
        end
        return AuraUtil.UnpackAuraData(auraData)
    end
end

-- endregion

--region Helper

function LibAPLHelper:New()
    local o = {
        reaction = 0.1,
        time = 0,
        cacheAura = {},
        cacheSpells = {},
    }
    setmetatable(o, self)
    self.__index = self
    o:ResetCache()
    return o
end

function LibAPLHelper:ResetCache()
    self.reaction = 0.1
    self.time = GetTime()
    self.gcd = self:GetSpellCooldownNoCache(61304) -- 61304 is Global Cooldown
    self.autoattack = self:GetSpellCooldownNoCache(6603) -- 6603 is Auto Attack
    self.cacheAura = {}
    self.cacheSpells = {}
end

function LibAPLHelper:HealthPercent(unit)
    return UnitHealth(unit) / UnitHealthMax(unit)
end

function LibAPLHelper:PowerPercent(unit, powertype)
    return UnitPower(unit, powertype) / UnitPowerMax(unit, powertype)
end

function LibAPLHelper:GetSpellCooldownNoCache(spellId)
    local ret = 0
    ---@diagnostic disable-next-line: deprecated
    local start, duration = GetSpellCooldown(spellId)
    if 0 < start and 0 < duration then
        ret = start + duration - self.time
    end
    return ret
end

function LibAPLHelper:GetSpellCooldown(spellId)
    local ret = 0
    if self.cacheSpells[spellId] then
        return self.cacheSpells[spellId]
    else
        ret = self:GetSpellCooldownNoCache(spellId)
        self.cacheSpells[spellId] = ret
    end
    return ret
end

function LibAPLHelper:IsSpellReady(spellId)
    return self:GetSpellCooldown(spellId) <= self.gcd
end

function LibAPLHelper:GenerateAuraCache(unit)
    local cache = {}
    for _, filter in ipairs( {"HELPFUL", "HARMFUL"} ) do
        for i = 1, 255 do
            local name, _, count, _, _, expiration, _, _, _, spellId = UnitAura(unit, i, filter)
            if not name or not spellId then
                break
            end
            local left = math.huge
            if 0 < expiration then
                left = expiration - self.time
            end
            spellId = tostring(spellId)
            cache[spellId] = {left, count}
            cache[name] = {left, count}
        end
    end
    self.cacheAura[unit] = cache
end

function LibAPLHelper:GetAura(unit, spellId)
    if not self.cacheAura[unit] then
        self:GenerateAuraCache(unit)
    end
    spellId = tostring(spellId)
    local cached = self.cacheAura[unit][spellId]
    if cached then
        return cached[1], cached[2]
    end
    return nil, nil
end

local UnitMap = {
    Player = "player",
    Target = "target",
    Pet = "pet",
    Self = "player", --??
    CurrentTarget = "target",
    AllPlayers = "??", --??
    AllTargets = "??", --??
}

function LibAPLHelper:UnitMap(aplUnit, default)
    local unit = default
    if aplUnit then
        unit = UnitMap[aplUnit]
    end
    return unit
end

function LibAPLHelper:IsExecutePhase(aplExecuteKey)
    if aplExecuteKey == "E90" then
        return 90 < self:HealthPercent("target")
    else
        local pct = tonumber(aplExecuteKey:sub(2))
        return self:HealthPercent("target") <= pct
    end
end

function LibAPLHelper:GetNumTargetsNearby()
    local num = 0
    local nameplates = C_NamePlate.GetNamePlates()
    for i=1,#nameplates 
    do
        local unit = nameplates[i].namePlateUnitToken
        if UnitCanAttack("player", unit) and self:CheckRange(unit, 8, "<=")
        then
            num = num + 1
        end
    end
    return num
end

function LibAPLHelper:CheckRange(unit, range, operator)
    local min, max = LibRangeCheck:GetRange(unit, true);
    if (type(range) ~= "number") then
        range = tonumber(range);
    end
    if (not range) then
        return
    end
    if (operator == "<=") then
        return (max or 999) <= range;
    else
        return (min or 0) >= range;
    end
end

local function HelperEventsFunction(self, event, arg1)
    -- Lightweight events only
	if event == "PLAYER_REGEN_DISABLED" then
		self.__last_combat_start = GetTime()
    elseif event == "ENCOUNTER_START" then
		self.__last_encounter = tonumber(arg1)
    elseif event == "ENCOUNTER_END" then
		self.__last_encounter = nil
	end
end

local HelperEventsFrame = CreateFrame("Frame")
HelperEventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
HelperEventsFrame:RegisterEvent("ENCOUNTER_START")
HelperEventsFrame:RegisterEvent("ENCOUNTER_END")
HelperEventsFrame:SetScript("OnEvent", HelperEventsFunction)

function LibAPLHelper:GetCombatTime()
    if UnitAffectingCombat("player") and HelperEventsFrame.__last_combat_start then
        return self.time - HelperEventsFrame.__last_combat_start
    end
    return 0
end

function LibAPLHelper:GetEncounterId()
    return HelperEventsFrame.__last_encounter
end

--endregion
