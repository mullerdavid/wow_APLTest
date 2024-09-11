--region LibStub

local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibAPL-1.0", 1

---@class LibAPL-1.0
---@field apl table
---@field prepull? table
---@field external? table
---@field sequences table<string, Sequence>
---@field sequence_stack table<string>
---@field timeout number
local LibAPL = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibAPL then
    return
end

local LibAPLHelper = LibStub:GetLibrary("LibAPLHelper-1.0")

--endregion

--[[
Actions:
    castSpell (castFriendlySpell)
    strictSequence
    sequence
    resetSequence
    channelSpell
    activateAura
    cancelAura
    multidot
    multiShield
    waitUntil ???
    autocastOtherCooldowns is silently eaten
    
    https://github.com/wowsims/cata/blob/12776383d4ec556e69b1870fd0587accfb794bf8/proto/apl.proto
    
    JSON.stringify(JSON.parse(localStorage.getItem("__cata_combat_rogue__currentSettings__")).player.rotation)
    JSON.stringify(JSON.parse(localStorage.getItem("__cata_combat_rogue__savedRotation__")).rotation_name.rotation)
--]]

--region Libs, constants

local SPELL_POWER_MANA = 0
local SPELL_POWER_RAGE = 1
local SPELL_POWER_FOCUS = 2
local SPELL_POWER_ENERGY = 3

--endregion

--region Debug

local Debug = {}
local Logger = {}

function Logger.Warning(...)
	print("\124cFFFFFF00[APL]", table.concat({...}, " "), "\124r")
end

local FuncsUnknown = {}
function Logger.Unknown(func)
    if not FuncsUnknown[func] then
        Logger.Warning(func, "is not known!")
        FuncsUnknown[func] = true
    end
end

local FuncsNotImplemented = {}
function Logger.NotImplemented(func)
    if not FuncsNotImplemented[func] then
        Logger.Warning(func, "is not implemented!")
        FuncsNotImplemented[func] = true
    end
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

--region Sequence

---@class Sequence
---@field actions table
---@field strict boolean
---@field idx number
---@field last_activity number
---@field timeout? number
local Sequence = {}

local function ActionsEqual(a, b)
    -- TODO: check properly
    if a.castSpell and b.castSpell then
        return a.castSpell.spellId.spellId == b.castSpell.spellId.spellId
    end
    return false
end

function Sequence:New(actions, strict, timeout)
    local o = {
        actions = actions, -- TODO: flatten other strictsequnces ??
        strict = strict or false,
        idx = 1,
        last_activity = GetTime(),
        timeout = timeout,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function Sequence:Timouted()
    return self.timeout and (self.last_activity + self.timeout) < GetTime()
end

function Sequence:Finished()
    return #self.actions < self.idx or (self.timeout and (self.last_activity + self.timeout) < GetTime())
end

function Sequence:Next()
    return self.actions[self.idx]
end

function Sequence:Step()
    self.last_activity = GetTime()
    self.idx = self.idx + 1
end

function Sequence:StepIfNext(action)
    local next = self:Next()
    if ActionsEqual(next, action) then
        self:Step()
    end
end

function Sequence:Reset()
    self.idx = 1
end

function Sequence:Activity()
    self.last_activity = GetTime()
end

--endregion

--region APLInterpreter

---@class APLInterpreter
---@field helper LibAPLHelper-1.0
---@field external_functions table
local APLInterpreter = {}

function APLInterpreter:New(external)
    local o = {
        helper = LibAPLHelper:New(),
        external_functions = external,
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
            Logger.Unknown("Condition "..key)
            return nil
        end
    end
end

function APLInterpreter:external(level, val)
    if self.external_functions and self.external_functions[val] then
        local ret = self.external_functions[val]()
        Debug.DebugLev(level+1, "external", val.."()", "=", ret)
        return ret
    end
    Logger.Unknown("External "..val)
    return false
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
        Logger.Unknown("Comparison "..op)
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
        Logger.Unknown("Math operator "..op)
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

-- Also handling external functions in the form of external:<name> for compatibility
function APLInterpreter:const(level, vals)
    local ret = vals.val
    local external = string.match(vals.val, "^external:(.*)")
    if external then
        ret = self:external(level+1, external)
    else
        Debug.DebugLev(level, "const", "=", ret)
    end
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

function APLInterpreter:currentRunicPower(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentRunicPower")
    Debug.DebugLev(level, "currentRunicPower", "=", ret)
    return ret
end

function APLInterpreter:currentSolarEnergy(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentSolarEnergy")
    Debug.DebugLev(level, "currentSolarEnergy", "=", ret)
    return ret
end

function APLInterpreter:currentLunarEnergy(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentLunarEnergy")
    Debug.DebugLev(level, "currentLunarEnergy", "=", ret)
    return ret
end

function APLInterpreter:currentHolyPower(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentHolyPower")
    Debug.DebugLev(level, "currentHolyPower", "=", ret)
    return ret
end

function APLInterpreter:currentRuneCount(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentRuneCount")
    Debug.DebugLev(level, "currentRuneCount", "=", ret)
    return ret
end

function APLInterpreter:currentNonDeathRuneCount(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentNonDeathRuneCount")
    Debug.DebugLev(level, "currentNonDeathRuneCount", "=", ret)
    return ret
end

function APLInterpreter:currentRuneDeath(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentRuneDeath")
    Debug.DebugLev(level, "currentRuneDeath", "=", ret)
    return ret
end

function APLInterpreter:currentRuneActive(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("currentRuneActive")
    Debug.DebugLev(level, "currentRuneActive", "=", ret)
    return ret
end

function APLInterpreter:runeCooldown(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("runeCooldown")
    Debug.DebugLev(level, "runeCooldown", "=", ret)
    return ret
end

function APLInterpreter:nextRuneCooldown(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("nextRuneCooldown")
    Debug.DebugLev(level, "nextRuneCooldown", "=", ret)
    return ret
end

function APLInterpreter:runeSlotCooldown(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("runeSlotCooldown")
    Debug.DebugLev(level, "runeSlotCooldown", "=", ret)
    return ret
end

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

function APLInterpreter:AuraIsActiveWithReactionTime(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    local left = self.helper:GetAura(unit, spellId) or 0
    local ret = self.helper.reaction < left
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

function APLInterpreter:auraIsKnown(level, vals)
    local spellId = vals.auraId.spellId
    local ret = false
    -- TODO: implement, need database for sources
    Logger.NotImplemented("auraIsKnown")
    Debug.DebugLev(level, "auraIsKnown", spellId, "=", ret)
    return ret
end

function APLInterpreter:auraNumStacks(level, vals)
    local unit = self.helper:UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    local _, count = self.helper:GetAura(unit, spellId)
    local ret = count or 0
    Debug.DebugLev(level, "auraNumStacks", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:auraShouldRefresh(level, vals)
    local spellId = vals.auraId.spellId
    local ret = false
    -- TODO: implement, maxOverlap 
    Logger.NotImplemented("auraShouldRefresh")
    Debug.DebugLev(level, "auraShouldRefresh", spellId, "=", ret)
    return ret
end

function APLInterpreter:dotTickFrequency(level, vals)
    local spellId = vals.auraId.spellId
    local ret = false
    -- TODO: implement, need database it?
    Logger.NotImplemented("dotTickFrequency")
    Debug.DebugLev(level, "dotTickFrequency", spellId, "=", ret)
    return ret
end

function APLInterpreter:auraInternalCooldown(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("auraInternalCooldown")
    Debug.DebugLev(level, "auraInternalCooldown", "=", ret)
end

function APLInterpreter:auraIcdIsReadyWithReactionTime(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("auraIcdIsReadyWithReactionTime")
    Debug.DebugLev(level, "auraIcdIsReadyWithReactionTime", "=", ret)
end

function APLInterpreter:spellTimeToReady(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self.helper:GetSpellCooldown(spellId)
    Debug.DebugLev(level, "spellTimeToReady", spellId, "=", ret)
    return ret
end

function APLInterpreter:spellIsReady(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self.helper:IsSpellReady(spellId)
    Debug.DebugLev(level, "spellIsReady", spellId, "=", ret)
    return ret
end

function APLInterpreter:currentTime(level)
    local ret = self.helper:GetCombatTime()
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
    local health = self.helper:HealthPercent("target")
    local encounter = self.helper:GetEncounterId()
    local ret = 30
    if encounter and health > 95 then
        -- rough estimate for 3 minutes boss fight
        ret = health * 3 * 60
    elseif not encounter and health > 85 then
        -- rough estimate for 30 seconds normal fight
        ret = health * 30
    else
        -- rough estimate based on health
        local ellapsed = self.helper:GetCombatTime()
        ret = ellapsed * health / (1-health)
    end
    ret = self.helper:HealthPercent("target") * 3 * 60
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
    Logger.NotImplemented("frontOfTarget")
    Debug.DebugLev(level, "frontOfTarget", "=", ret)
    return ret
end

function APLInterpreter:bossSpellIsCasting(level)
    local ret = false
    -- TODO: implement
    Logger.NotImplemented("bossSpellIsCasting")
    Debug.DebugLev(level, "bossSpellIsCasting", "=", ret)
end

function APLInterpreter:bossSpellTimeToReady(level)
    local ret = 0
    -- TODO: possible? dbm?
    Logger.NotImplemented("bossSpellTimeToReady")
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

function APLInterpreter:autoTimeToNext(level)
    local ret = self.helper.autoattack
    Debug.DebugLev(level, "autoTimeToNext", "=", ret)
end

function APLInterpreter:spellIsKnown(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellIsKnown")
    Debug.DebugLev(level, "spellIsKnown", "=", ret)
end

function APLInterpreter:spellCanCast(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellCanCast")
    Debug.DebugLev(level, "spellCanCast", "=", ret)
end

function APLInterpreter:spellTravelTime(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellTravelTime")
    Debug.DebugLev(level, "spellTravelTime", "=", ret)
end

function APLInterpreter:spellCpm(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellCpm")
    Debug.DebugLev(level, "spellCpm", "=", ret)
end

function APLInterpreter:spellIsChanneling(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellIsChanneling")
    Debug.DebugLev(level, "spellIsChanneling", "=", ret)
end

function APLInterpreter:spellChanneledTicks(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellChanneledTicks")
    Debug.DebugLev(level, "spellChanneledTicks", "=", ret)
end

function APLInterpreter:spellCurrentCost(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("spellCurrentCost")
    Debug.DebugLev(level, "spellCurrentCost", "=", ret)
end

function APLInterpreter:channelClipDelay(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("channelClipDelay")
    Debug.DebugLev(level, "channelClipDelay", "=", ret)
end

function APLInterpreter:inputDelay(level, vals)
    local ret = self.helper.reaction
    Debug.DebugLev(level, "inputDelay", "=", ret)
end

function APLInterpreter:totemRemainingTime(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("totemRemainingTime")
    Debug.DebugLev(level, "totemRemainingTime", "=", ret)
end

function APLInterpreter:catExcessEnergy(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("catExcessEnergy")
    Debug.DebugLev(level, "catExcessEnergy", "=", ret)
end

function APLInterpreter:catNewSavageRoarDuration(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("catNewSavageRoarDuration")
    Debug.DebugLev(level, "catNewSavageRoarDuration", "=", ret)
end

function APLInterpreter:warlockShouldRecastDrainSoul(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("warlockShouldRecastDrainSoul")
    Debug.DebugLev(level, "warlockShouldRecastDrainSoul", "=", ret)
end

function APLInterpreter:warlockShouldRefreshCorruption(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("warlockShouldRefreshCorruption")
    Debug.DebugLev(level, "warlockShouldRefreshCorruption", "=", ret)
end

function APLInterpreter:druidCurrentEclipsePhase(level)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("druidCurrentEclipsePhase")
    Debug.DebugLev(level, "druidCurrentEclipsePhase", "=", ret)
end

function APLInterpreter:sequenceIsComplete(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("sequenceIsComplete")
    Debug.DebugLev(level, "sequenceIsComplete", "=", ret)
end

function APLInterpreter:sequenceIsReady(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("sequenceIsReady")
    Debug.DebugLev(level, "sequenceIsReady", "=", ret)
end

function APLInterpreter:sequenceTimeToReady(level, vals)
    local ret = 0
    -- TODO: implement
    Logger.NotImplemented("sequenceTimeToReady")
    Debug.DebugLev(level, "sequenceTimeToReady", "=", ret)
end

--endregion

--region LibAPL

---Creates new APL object, accepts WoWSimAPL like table, (strict sequence) timeout (default 15s), 
---@param apltable table WoWSimAPL like table
---@param timeout? number Strict sequence timeout (default 15s)
---@param external? table External functions table
---@param auto_step? boolean Automatically step through sequences based on the casts (maximum 5 concurrent runners!)
---@return LibAPL-1.0
function LibAPL:New(apltable, timeout, external, auto_step)
    if apltable.type ~= "TypeAPL" then
        error("invalid apl")
    end
    local o = {
        apl = apltable.priorityList,
        prepull = apltable.prepullActions,
        external = external,
        sequences = {},
        sequence_stack = {},
        timeout = timeout or 15
    }
    setmetatable(o, self)
    self.__index = self
    if auto_step then
        LibAPLHelper.Global.RegisterStepper(o)
    end
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

local key_counter = 0
local function SequenceKey()
    key_counter = key_counter + 1
    local key = "unnamed-sequence-"..key_counter
    return key
end

---@param self LibAPL-1.0
---@param action table
local function AddSequenceIfNotExists(self, action)
    if not action.name then
        action.name = SequenceKey()
    end
    if not self.sequences[action.name] then
        local sequence
        if action.strictSequence then
            sequence = Sequence:New(action.strictSequence.actions, true, self.timeout)
        elseif action.sequence then
            sequence = Sequence:New(action.sequence.actions)
        end
        self.sequences[action.name] = sequence
    else
        self.sequences[action.name]:Activity()
    end
end

---Returns if we handle the action and if the action should be overriden
---@param self LibAPL-1.0
---@param action table
---@return boolean, table?
local function HandleAction(self, action)
    if action.autocastOtherCooldowns then
        return false
    elseif action.strictSequence then
        AddSequenceIfNotExists(self, action)
        if self.sequence_stack[#self.sequence_stack] ~= action.name then
            self.sequence_stack[#self.sequence_stack + 1] = action.name
        end
        return true, {strictSequence = {name = action.name}}
    elseif action.sequence then
        AddSequenceIfNotExists(self, action)
        if self.sequence_stack[#self.sequence_stack] ~= action.name then
            self.sequence_stack[#self.sequence_stack + 1] = action.name
        end
        return true, {sequence = {name = action.name}}
    elseif action.resetsequence then
        local name = action.resetsequence.sequenceName
        self.sequences[name]:Reset()
        -- maybe restart from start afterwards?
        return false
    else
        return true
    end
end

---@param self LibAPL-1.0
local function HasStrictSequenceActive(self)
    for i = #self.sequence_stack, 1, -1 do
        local seq = self.sequences[self.sequence_stack[i]]
        if seq:Finished() or seq:Timouted() then
            if seq.strict then
                seq:Reset()
            end
            table.remove(self.sequence_stack, i)
        elseif seq.strict then
            return true
        end
    end
    return false
end

local function SecondsToNumber(str)
    if string.sub(str, -1) == "s" then
        str = string.sub(str, 1, -2)
    end
    return tonumber(str)
end

---@param self LibAPL-1.0
---@return table, ...
function LibAPL:GetPrePullActions(prepull_left)
    local max_seconds = 3
    local actions = {}
    Debug.DebugClear()
    Debug.DebugLev(0, -1*prepull_left)
    -- assuming ordered prepull list
    for i = 1, #self.prepull do
        local item = self.prepull[i]
        if item.doAtValue and item.doAtValue.const and item.doAtValue.const.val then
            local do_at = -1* SecondsToNumber(item.doAtValue.const.val)
            local left = prepull_left - do_at
            if 0 < left and left < max_seconds then
                local act = item.action
                local handled, override = HandleAction(self, act)
                if handled then
                    actions[#actions+1] = {prepull={left=left, max=max_seconds, action=override or act}}
                    if act.activateAura then
                        Debug.DebugLev(1, "activateAura", act.activateAura.auraId.spellId)
                    elseif act.castSpell then
                        Debug.DebugLev(1, "castSpell", act.castSpell.spellId.spellId or act.castSpell.spellId.otherId)
                    end
                end
            end
        end
    end
    return unpack(actions)
end

function LibAPL:Run()
    if self.prepull then
        local prepull_left = LibAPLHelper.Global.PrePullLeft()
        if 0 < prepull_left then
            return self:GetPrePullActions(prepull_left)
        end
    end
    if HasStrictSequenceActive(self) then
        local name = self.sequence_stack[#self.sequence_stack]
        return {strictSequence = {name = name}}
    end
    return self:Interpret()
end

function LibAPL:SequenceNext()
    if 0 < #self.sequence_stack then
        while true do
            local seq = self.sequences[self.sequence_stack[#self.sequence_stack]]
            local act = seq:Next()
            local handled, override = HandleAction(self, act)
            if handled then
                if not override then
                    return act
                else
                    seq:Step()
                end
            else
                seq:Step()
            end
        end
    end
    return nil
end

function LibAPL:SequenceStep(action)
    if 0 < #self.sequence_stack then
        local seq = self.sequences[self.sequence_stack[#self.sequence_stack]]
        if action ~= nil then
            seq:StepIfNext(action)
        else
            seq:Step()
        end
    end
end

function LibAPL:SequenceClear()
    self.sequence_stack.remove(#self.sequence_stack)
end

function LibAPL:SequenceClearAll()
    self.sequence_stack = {}
end

---@return table?, ...
function LibAPL:Interpret()
    local interpreter = APLInterpreter:New(self.external)
    for _,val in ipairs(self.apl) do
        local act = val.action
        if not val.hide then
            Debug.DebugClear()
            Debug.Debug(interpreter.helper:GetCombatTime())
            local cond = act.condition == nil or interpreter:EvalCondition(-1, act.condition)
            if cond then
                local handled, override = HandleAction(self, act)
                if handled then
                    if Debug.__debug and override and override.strictSequence then
                        local seq = self.sequences[self.sequence_stack[#self.sequence_stack]]
                        Debug.DebugLev(0, "Strict Sequence Mode")
                        for _,v in ipairs(seq.actions) do
                            Debug.DebugLev(1, v.castSpell.spellId.spellId)
                        end
                    end
                    return override or act
                end
            end
        end
    end
    return nil
end

--endregion