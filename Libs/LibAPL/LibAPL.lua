--region LibStub

local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibAPL-1.0", 1

---@class LibAPL-1.0
---@field apl table
---@field strictSequence? Sequence
---@field timeout number
local LibAPL = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibAPL then
    return
end

local LibAPLHelper = LibStub:GetLibrary("LibAPLHelper-1.0")

--endregion

--[[
Actions:
    CastSpell (CastFriendlySpell)
    StrictSequence
    Sequence (if has no name, generate random uuid and assign it on tree)
    ResetSequence
    ChannelSpell
    ActivateAura
    CancelAura
    Multidot
    MultiShield
    WaitUntil ???
    AutocastOtherCooldowns ???
--]]

--[[
TODO:
Sequence related stuff
Prepull
wowsim extension - external functions/variables from outside, preprocess for const that starts with "external:" for interoparability
aura/dot source?

caching compute heavy stuff

https://github.com/wowsims/cata/blob/12776383d4ec556e69b1870fd0587accfb794bf8/proto/apl.proto

JSON.stringify(JSON.parse(localStorage.getItem("__cata_assassination_rogue__currentSettings__")).player.rotation)

Datastore?
LibDRM?
]]--

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
	print("\124cFFFFFF00[APL]", ..., "\124r")
end

local FuncsUnknown = {}
function Logger.Unknown(func)
    if not FuncsUnknown[func] then
        Logger.Warning(func, "is not unknown!")
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
---@field idx number
---@field last_activity number
---@field timeout? number
local Sequence = {}

local function ActionsEqual(a, b)
    return a == b -- TODO: check properly
end

function Sequence:New(actions, timeout)
    local o = {
        actions = actions, -- TODO: flatten other strictsequnces ??
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
    next = self:Next()
    if ActionsEqual(next, action) then
        self:Step()
    end
end

--endregion

--region APLInterpreter

---@class APLInterpreter
---@field helper LibAPLHelper-1.0
local APLInterpreter = {}

function APLInterpreter:New()
    local o = {
        helper = LibAPLHelper:New(),
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
        Logger.Unknown("Cmparison "..op)
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

---Creates new APL object, accepts WoWSimAPL like table and (strict sequence) timeout (default 15s)
---@param apltable table
---@param timeout? number
---@return LibAPL-1.0
function LibAPL:New(apltable, timeout)
    if apltable.type ~= "TypeAPL" then
        error("invalid apl")
    end
    local o = {
        apl = apltable.priorityList,
        strictSequence = nil,
        timeout = timeout or 15
    }
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
    if self.strictSequence ~= nil then
        if self.strictSequence:Finished() or self.strictSequence:Timouted() then
            self:StrictSequenceClear()
        else
            return "strictSequence"
        end
    end
    return self:Interpret()
end

function LibAPL:StrictSequenceNext()
    if self.strictSequence ~= nil then
        return select(2, self:HandleAction(self.strictSequence:Next()))
    end
    return nil
end

function LibAPL:StrictSequenceClear()
    self.strictSequence = nil
end

local function ExtractFirstKey(tab)
    for k,_ in pairs(tab) do
        return tostring(k)
    end
    return "<empty>"
end

---Returns if we handle the action and the action converted from WoWSimAPL to LibAPL
---@return boolean, string?, ...
function LibAPL:HandleAction(action)
    if action.autocastOtherCooldowns then
        return false
    elseif action.strictSequence then
        self.strictSequence = Sequence:New(action.strictSequence.actions, self.timeout)
        return true, "strictSequence"
    elseif action.castSpell then
        local vals = action.castSpell
        return true, "castSpell", vals.spellId.spellId
    else
        Logger.Warning("unknown action " + ExtractFirstKey(action))
        return true
    end
end

---@return string?, ...
function LibAPL:Interpret()
    local interpreter = APLInterpreter:New()
    for _,val in ipairs(self.apl) do
        local act = val.action
        if not val.hide then
            Debug.DebugClear()
            Debug.Debug(interpreter.helper:GetCombatTime())
            local cond = act.condition == nil or interpreter:EvalCondition(-1, act.condition)
            if cond then
                local ret = {self:HandleAction(act)}
                local handled = ret[1]
                if handled then
                    return select(2, unpack(ret))
                end
            end
        end
    end
    return nil
end

--endregion