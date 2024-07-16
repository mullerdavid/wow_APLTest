--[[
Prepull
Sequence related stuff
wowsim extension - variables from outside

move helper/getter functions to own class for reusability
caching compute heavy stuff

https://github.com/wowsims/wotlk/blob/7597c28d4145c235d001f0242e3c99c0f8edbdb8/proto/apl.proto

JSON.stringify(JSON.parse(localStorage.getItem("__cata_assassination_rogue__currentSettings__")).player.rotation)

Datastore?
]]--

--region LibStub

local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibAPL-1.0", 1

---@class LibAPL-1.0
---@field apl table
local LibAPL = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibAPL then
    return
end

--endregion

--region Libs, constants

local LibRangeCheck = LibStub("LibRangeCheck-3.0")
local SPELL_POWER_MANA = 0
local SPELL_POWER_RAGE = 1
local SPELL_POWER_FOCUS = 2
local SPELL_POWER_ENERGY = 3

--endregion

--region Debug

local Debug = {}
local Logger = {}

function Logger.Warning(...)
	print("\124cFFFFFF00[APL]", ..., "\124r")
end

function Debug.DumpVar(arg, name)
	if Debug.__dump then
        Debug.__dump(arg, name)
    end
end

function Debug.DebugClear()
	if Debug.__clear then
        Debug.__clear()
    end
end

function Debug.Debug(...)
	if Debug.__debug then
        Debug.__debug(...)
    end
end

function Debug.DebugLev(level, ...)
	if Debug.__debug then
        Debug.__debug(string.rep("  ", level), ...)
    end
end

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

---@class Helper
---@field time number
---@field gcd number
---@field cacheAura table
---@field cacheSpells table
local Helper = {}

function Helper:New()
    local o = {
        time = 0,
        cacheAura = {},
        cacheSpells = {},
    }
    setmetatable(o, self)
    self.__index = self
    o:ResetCache()
    return o
end

function Helper:ResetCache()
    self.time = GetTime()
    self.gcd = self:GetSpellCooldownNoCache(61304) -- 61304 is Global Cooldown
    self.cacheAura = {}
    self.cacheSpells = {}
end

function Helper:HealthPercent(unit)
    return UnitHealth(unit) / UnitHealthMax(unit)
end

function Helper:PowerPercent(unit, powertype)
    return UnitPower(unit, powertype) / UnitPowerMax(unit, powertype)
end

function Helper:GetSpellCooldownNoCache(spellId)
    local ret = 0
    local start, duration = GetSpellCooldown(spellId)
    if 0 < start and 0 < duration then
        ret = start + duration - self.time
    end
    return ret
end

function Helper:GetSpellCooldown(spellId)
    local ret = 0
    if self.cacheSpells[spellId] then
        return self.cacheSpells[spellId]
    else
        ret = self:GetSpellCooldownNoCache(spellId)
        self.cacheSpells[spellId] = ret
    end
    return ret
end

function Helper:IsSpellReady(spellId)
    return self:GetSpellCooldown(spellId) <= self.gcd
end

function Helper:GenerateAuraCache(unit)
    if self.cacheAura[unit] then
        return
    end
    local cache = {}
    for _, filter in ipairs( {"HELPFUL", "HARMFUL"} ) do
        for i = 1, 255 do
            local name, _, _, _, _, expiration, _, _, _, spellId = UnitAura(unit, i, filter)
            if not name or not spellId then
                break
            end
            local left = math.huge
            if 0<expiration then
                left = expiration - self.time
            end
            cache[spellId] = left
            cache[name] = left
        end
    end
    self.cacheAura[unit] = cache
end

function Helper:GetAura(unit, spellId)
    self:GenerateAuraCache(unit)
    return self.cacheAura[unit][spellId]
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

function Helper:UnitMap(aplUnit, default)
    local unit = default
    if aplUnit then
        unit = UnitMap[aplUnit]
    end
    return unit
end

function Helper:IsExecutePhase(aplExecuteKey)
    if aplExecuteKey == "E90" then
        return 90 < self:HealthPercent("target")
    else
        local pct = tonumber(aplExecuteKey:sub(2))
        return self:HealthPercent("target") <= pct
    end
end

function Helper:GetNumTargetsNearby()
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

function Helper:CheckRange(unit, range, operator)
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
	if event == "PLAYER_REGEN_DISABLED" then
		self.__last_combat_start = GetTime()
	end
end

local HelperEventsFrame = CreateFrame("Frame")
HelperEventsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
HelperEventsFrame:SetScript("OnEvent", HelperEventsFunction)

function Helper:CombatTime()
    if UnitAffectingCombat("player") and HelperEventsFrame.__last_combat_start then
        return self.time - HelperEventsFrame.__last_combat_start
    end
    return 0
end

--endregion

--region APLInterpreter

---@class APLInterpreter
---@field helper Helper
local APLInterpreter = {}

function APLInterpreter:New()
    local o = {
        helper = Helper:New(),
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function APLInterpreter:EvalCondition(level, condition)
    for key,val in pairs(condition) do
        if self[key] then
            return self[key](self, level+1, val)
        else
            Logger.Warning("unknown condition", key)
            return nil
        end
    end
end

APLInterpreter["and"] = function(self, level, vals)
    Debug.DebugLev(level, "and")
    local ret = true
    for _,val in ipairs(vals.vals) do
        if not self:EvalCondition(level+1, val) then
            ret = false
            break
        end
    end
    Debug.DebugLev(level+1, "result", ret)
    return ret
end

APLInterpreter["or"] = function(self, level, vals)
    Debug.DebugLev(level, "or")
    local ret = false
    for _,val in ipairs(vals.vals) do
        if self:EvalCondition(level+1, val) then
            ret = true
            break
        end
    end
    Debug.DebugLev(level+1, "result", ret)
    return ret
end

APLInterpreter["not"] = function(self, level, vals)
    Debug.DebugLev(level, "not")
    local ret = not self:EvalCondition(level+1, vals.val)
    Debug.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:max(level, vals)
    Debug.DebugLev(level, "max")
    local ret = nil
    for _,val in ipairs(vals.vals) do
        local eval = tonumber(self:EvalCondition(level+1, val))
        if ret == nil or ret < eval then
            ret = eval
        end
    end
    Debug.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:min(level, vals)
    Debug.DebugLev(level, "min")
    local ret = nil
    for _,val in ipairs(vals.vals) do
        local eval = tonumber(self:EvalCondition(level+1, val))
        if ret == nil or eval < ret then
            ret = eval
        end
    end
    Debug.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:cmp(level, vals)
    local op = vals.op
    Debug.DebugLev(level, "cmp")
    if self[op] then
        local ret = self[op](self, level+1, vals.lhs, vals.rhs)
        Debug.DebugLev(level+1, "result", ret)
        return ret
    else
        Logger.Warning("unknown comparison", op)
        return nil
    end
end

function APLInterpreter:math(level, vals)
    local op = vals.op
    Debug.DebugLev(level, "math")
    if self[op] then
        local ret = self[op](self, level+1, vals.lhs, vals.rhs)
        Debug.DebugLev(level+1, "result", ret)
        return ret
    else
        Logger.Warning("unknown math", op)
        return nil
    end
end

function APLInterpreter:__binop_eval_tonumber(level, lhs, rhs)
    local elhs = tonumber(self:EvalCondition(level, lhs))
    local erhs = tonumber(self:EvalCondition(level, rhs))
    return elhs, erhs
end

function APLInterpreter:OpEq(level, lhs, rhs)
    Debug.DebugLev(level, "OpEq =")
    local elhs = self:EvalCondition(level+1, lhs)
    local erhs = self:EvalCondition(level+1, rhs)
    return elhs == erhs or tonumber(elhs) == tonumber(erhs)
end

function APLInterpreter:OpLt(level, lhs, rhs)
    Debug.DebugLev(level, "OpLt <")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs < erhs
end

function APLInterpreter:OpLe(level, lhs, rhs)
    Debug.DebugLev(level, "OpLe <=")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs <= erhs
end

function APLInterpreter:OpGt(level, lhs, rhs)
    Debug.DebugLev(level, "OpGt >")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs > erhs
end

function APLInterpreter:OpGe(level, lhs, rhs)
    Debug.DebugLev(level, "OpGe >=")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs >= erhs
end

function APLInterpreter:OpAdd(level, lhs, rhs)
    Debug.DebugLev(level, "OpAdd +")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs + erhs
end

function APLInterpreter:OpSub(level, lhs, rhs)
    Debug.DebugLev(level, "OpSub -")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs - erhs
end

function APLInterpreter:OpMul(level, lhs, rhs)
    Debug.DebugLev(level, "OpMul *")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs * erhs
end

function APLInterpreter:OpDiv(level, lhs, rhs)
    Debug.DebugLev(level, "OpDiv /")
    local elhs, erhs = self:__binop_eval_tonumber(level+1, lhs, rhs)
    return elhs / erhs
end

function APLInterpreter:const(level, vals)
    local ret = vals.val
    Debug.DebugLev(level, "const", "=", ret)
    return ret
end

function APLInterpreter:currentHealth(level)
    local ret = UnitHealth("player")
    Debug.DebugLev(level, "currentHealth", "=", ret)
    return ret
end

function APLInterpreter:currentHealthPercent(level)
    local ret = self.helper:HealthPercent("player")
    Debug.DebugLev(level, "currentHealthPercent", "=", ret)
    return ret
end

function APLInterpreter:currentMana(level)
    local ret = UnitPower("player", SPELL_POWER_MANA)
    Debug.DebugLev(level, "currentMana", "=", ret)
    return ret
end

function APLInterpreter:currentManaPercent(level)
    local ret = self.helper:PowerPercent("player", SPELL_POWER_MANA)
    Debug.DebugLev(level, "currentManaPercent", "=", ret)
    return ret
end

function APLInterpreter:currentRage(level)
    local ret = UnitPower("player", SPELL_POWER_RAGE)
    Debug.DebugLev(level, "currentRage", "=", ret)
    return ret
end

function APLInterpreter:currentFocus(level)
    local ret = UnitPower("player", SPELL_POWER_FOCUS)
    Debug.DebugLev(level, "currentFocus", "=", ret)
    return ret
end

function APLInterpreter:currentEnergy(level)
    local ret = UnitPower("player", SPELL_POWER_ENERGY)
    Debug.DebugLev(level, "currentEnergy", "=", ret)
    return ret
end

function APLInterpreter:currentComboPoints(level)
    local ret = GetComboPoints("player", "target")
    Debug.DebugLev(level, "currentComboPoints", "=", ret)
    return ret
end

-- TODO: runic power, runes

function APLInterpreter:unitIsMoving(level)
    local threshold = 0.01
    local ret = threshold < GetUnitSpeed("player")
    Debug.DebugLev(level, "unitIsMoving", "=", ret)
end

function APLInterpreter:auraIsActive(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    local ret = self.helper:GetAura(unit, spellId) ~= nil
    Debug.DebugLev(level, "auraIsActive", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:dotIsActive(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "target")
    local spellId = vals.spellId.spellId
    local ret = self.helper:GetAura(unit, spellId) or 0
    Debug.DebugLev(level, "dotIsActive", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:auraRemainingTime(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    local ret = self.helper:GetAura(unit, spellId) or 0
    Debug.DebugLev(level, "auraRemainingTime", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:dotRemainingTime(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "target")
    local spellId = vals.spellId.spellId
    local ret = self.helper:GetAura(unit, spellId) ~= nil
    Debug.DebugLev(level, "dotRemainingTime", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:spellTimeToready(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self.helper:GetSpellCooldown(spellId)
    Debug.DebugLev(level, "spellTimeToready", spellId, "=", ret)
    return ret
end

function APLInterpreter:spellIsReady(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self.helper:IsSpellReady(spellId)
    Debug.DebugLev(level, "spellIsReady", spellId, "=", ret)
    return ret
end

function APLInterpreter:currentTime(level)
    local ret = self.helper:CombatTime()
    Debug.DebugLev(level, "currentTime", "=", ret)
    return ret
end

function APLInterpreter:currentTimePercent(level)
    -- rough estimate based on health
    local ret = 1.0 - self.helper:HealthPercent("target")
    Debug.DebugLev(level, "currentTimePercent", "=", ret)
    return ret
end

function APLInterpreter:remainingTime(level)
    -- rough estimate for 3 minute fight
    local ret = self.helper:HealthPercent("target") * 3 * 60
    Debug.DebugLev(level, "remainingTime", "=", ret)
    return ret
end

function APLInterpreter:remainingTimePercent(level)
    -- rough estimate based on health
    local ret = self.helper:HealthPercent("target")
    Debug.DebugLev(level, "remainingTimePercent", "=", ret)
    return ret
end

function APLInterpreter:isExecutePhase(level, vals)
    local ret = self.helper:IsExecutePhase(vals.threshold)
    Debug.DebugLev(level, "IsExecutePhase", "=", ret)
    return ret
end

function APLInterpreter:numberTargets(level)
    local ret = self.helper:GetNumTargetsNearby()
    Debug.DebugLev(level, "numberTargets", "=", ret)
    return ret
end

function APLInterpreter:frontOfTarget(level)
    local ret = false
    -- TODO: possible?
    Debug.DebugLev(level, "frontOfTarget", "=", ret)
    return ret
end

function APLInterpreter:bossSpellIsCasting(level)
    -- TODO: implement
    local ret = false
    Debug.DebugLev(level, "bossSpellIsCasting", "=", ret)
end

function APLInterpreter:bossSpellTimeToReady(level)
    -- TODO: possible? dbm?
    local ret = 0
    Debug.DebugLev(level, "bossSpellTimeToReady", "=", ret)
end

function APLInterpreter:gcdTimeToReady(level)
    local ret = self.helper.gcd
    Debug.DebugLev(level, "gcdTimeToReady", "=", ret)
end

function APLInterpreter:gcdIsReady(level)
    local ret = self.helper.gcd <= 0
    Debug.DebugLev(level, "gcdIsReady", "=", ret)
end

-- TODO: autoTimeToNext

-- TODO: spell / aura stuff

--endregion

--region LibAPL

---Creates new APL object, accepts wowsim apl like table
---@param apltable table
---@return LibAPL-1.0
function LibAPL:New(apltable)
    if apltable.type ~= "TypeAPL" then
        error("invalid apl")
    end
    local o = { apl = apltable.priorityList, x = 1 }
    setmetatable(o, self)
    self.__index = self
    return o
end

function LibAPL:AttachDebugger(functionClear, functionDebug, functionDumpVar)
    Debug.__clear = functionClear
    Debug.__debug = functionDebug
    Debug.__dump = functionDumpVar
end

function LibAPL:DetachDebugger()
    Debug.__clear = nil
    Debug.__debug = nil
    Debug.__dump = nil
end

function LibAPL:Run()
    return self:Interpret()
end

function LibAPL:Interpret()
    local interpreter = APLInterpreter:New()
    for _,val in ipairs(self.apl) do
        local act = val.action
        if not val.hide then
            Debug.DebugClear()
            Debug.Debug(interpreter.helper:CombatTime())
            local cond = act.condition == nil or interpreter:EvalCondition(-1, act.condition)
            if cond then
                if act.autocastOtherCooldowns then
                    -- do nothing
                elseif act.strictSequence then
                    return "strictSequence", act.strictSequence
                elseif act.castSpell then
                    local vals = act.castSpell
                    -- final check if spell is ready
                    if interpreter:spellIsReady(1, vals) then
                        return "castSpell", vals.spellId.spellId
                    end
                else
                    Logger.Warning("unknown action")
                    return nil
                end
            end
        end
    end
    return nil
end

--endregion