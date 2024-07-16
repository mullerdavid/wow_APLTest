local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibAPL-1.0", 1

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

---@class LibAPL-1.0
---@field apl table
local LibAPL = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibAPL then
    return
end

local LibRangeCheck = LibStub("LibRangeCheck-3.0")

local L = {}
local SPELL_POWER_MANA = 0
local SPELL_POWER_RAGE = 1
local SPELL_POWER_FOCUS = 2
local SPELL_POWER_ENERGY = 3


function L.DebugVar(arg, name)
	name = name or "debug"
	DevTool.MainWindow:Show()
	DevTool:ClearAllData()
	DevTool:AddData(arg, name)
	DevTool:UpdateMainTableUI()
end

function L.Warning(...)
	print("[APL][Warn]", ...)
end

if true then
    local f = CreateFrame("Frame",nil,UIParent)
    f:SetWidth(1)
    f:SetHeight(1)
    f:SetPoint("TOPLEFT",32,-32)
    f.text = f:CreateFontString(nil,"ARTWORK") 
    f.text:SetFont("Fonts\\ARIALN.ttf", 12, "OUTLINE")
    f.text:SetPoint("TOPLEFT",0,0)
    f.text:SetJustifyH("LEFT")
    f.text:SetJustifyV("TOP")
    f:Show()
    L.DebugFrame = f
    L.DebugFrameText = ""
    f.text:SetText(L.DebugFrameText)
end

function L.DebugClear()
	L.DebugFrameText = ""
end

function L.Debug(...)
    for _,v in ipairs({...}) do
        L.DebugFrameText = L.DebugFrameText .. tostring(v) .. " "
    end
    L.DebugFrameText = L.DebugFrameText .. "\n"
    L.DebugFrame.text:SetText(L.DebugFrameText)
	--print("[APL][Debug]", ...)
end

function L.DebugLev(level, ...)
    L.Debug(string.rep("  ", level), ...)
end

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

---@class APLInterpreter
---@field time number
---@field cacheAura table
---@field cacheSpells table
local APLInterpreter = {}

function APLInterpreter:New()
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

function LibAPL:Run()
    return self:Interpret()
end

function LibAPL:Interpret()
    local interpreter = APLInterpreter:New()
    for _,val in ipairs(self.apl) do
        local act = val.action
        if not val.hide then
            L.DebugClear()
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
                    L.Warning("unknown action")
                    return nil
                end
            end
        end
    end
    return nil
end

function APLInterpreter:ResetCache()
    self.time = GetTime()
    self.cacheAura = {}
    self.cacheSpells = {}
    self.gcd = self:GetSpellCooldownNoCache(61304) -- 61304 is Global Cooldown
end

function APLInterpreter:EvalCondition(level, condition)
    for key,val in pairs(condition) do
        if self[key] then
            return self[key](self, level+1, val)
        else
            L.Warning("unknown condition", key)
            return nil
        end
    end
end

APLInterpreter["and"] = function(self, level, vals)
    L.DebugLev(level, "and")
    local ret = true
    for _,val in ipairs(vals.vals) do
        if not self:EvalCondition(level+1, val) then
            ret = false
            break
        end
    end
    L.DebugLev(level+1, "result", ret)
    return ret
end

APLInterpreter["or"] = function(self, level, vals)
    L.DebugLev(level, "or")
    local ret = false
    for _,val in ipairs(vals.vals) do
        if self:EvalCondition(level+1, val) then
            ret = true
            break
        end
    end
    L.DebugLev(level+1, "result", ret)
    return ret
end

APLInterpreter["not"] = function(self, level, vals)
    L.DebugLev(level, "not")
    local ret = not self:EvalCondition(level+1, vals.val)
    L.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:max(level, vals)
    L.DebugLev(level, "max")
    local ret = nil
    for _,val in ipairs(vals.vals) do
        local eval = tonumber(self:EvalCondition(level+1, val))
        if ret == nil or ret < eval then
            ret = eval
        end
    end
    L.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:min(level, vals)
    L.DebugLev(level, "min")
    local ret = nil
    for _,val in ipairs(vals.vals) do
        local eval = tonumber(self:EvalCondition(level+1, val))
        if ret == nil or eval < ret then
            ret = eval
        end
    end
    L.DebugLev(level+1, "result", ret)
    return ret
end

function APLInterpreter:cmp(level, vals)
    local op = vals.op
    L.DebugLev(level, "cmp")
    if self[op] then
        local ret = self[op](self, level+1, vals.lhs, vals.rhs)
        L.DebugLev(level+1, "result", ret)
        return ret
    else
        L.Warning("unknown comparison", op)
        return nil
    end
end

function APLInterpreter:math(level, vals)
    local op = vals.op
    L.DebugLev(level, "math")
    if self[op] then
        local ret = self[op](self, level+1, vals.lhs, vals.rhs)
        L.DebugLev(level+1, "result", ret)
        return ret
    else
        L.Warning("unknown math", op)
        return nil
    end
end

function APLInterpreter:OpEq(level, lhs, rhs)
    L.DebugLev(level, "OpEq =")
    local elhs = self:EvalCondition(level+1, lhs)
    local erhs = self:EvalCondition(level+1, rhs)
    return elhs == erhs or tonumber(elhs) == tonumber(erhs)
end

function APLInterpreter:OpLt(level, lhs, rhs)
    L.DebugLev(level, "OpLt <")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs < erhs
end

function APLInterpreter:OpLe(level, lhs, rhs)
    L.DebugLev(level, "OpLe <=")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs <= erhs
end

function APLInterpreter:OpGt(level, lhs, rhs)
    L.DebugLev(level, "OpGt >")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs > erhs
end

function APLInterpreter:OpGe(level, lhs, rhs)
    L.DebugLev(level, "OpGe >=")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs >= erhs
end

function APLInterpreter:OpAdd(level, lhs, rhs)
    L.DebugLev(level, "OpAdd +")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs + erhs
end

function APLInterpreter:OpSub(level, lhs, rhs)
    L.DebugLev(level, "OpSub -")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs - erhs
end

function APLInterpreter:OpMul(level, lhs, rhs)
    L.DebugLev(level, "OpMul *")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs * erhs
end

function APLInterpreter:OpDiv(level, lhs, rhs)
    L.DebugLev(level, "OpDiv /")
    local elhs = tonumber(self:EvalCondition(level+1, lhs))
    local erhs = tonumber(self:EvalCondition(level+1, rhs))
    return elhs / erhs
end

function APLInterpreter:const(level, vals)
    local ret = vals.val
    L.DebugLev(level, "const", "=", ret)
    return ret
end

function L.HealthPercent(unit)
    return UnitHealth(unit) / UnitHealthMax(unit)
end

function L.PowerPercent(unit, powertype)
    return UnitPower(unit, powertype) / UnitPowerMax(unit, powertype)
end

function APLInterpreter:currentHealth(level)
    local ret = UnitHealth("player")
    L.DebugLev(level, "currentHealth", "=", ret)
    return ret
end

function APLInterpreter:currentHealthPercent(level)
    local ret = L.HealthPercent("player")
    L.DebugLev(level, "currentHealthPercent", "=", ret)
    return ret
end

function APLInterpreter:currentMana(level)
    local ret = UnitPower("player", SPELL_POWER_MANA)
    L.DebugLev(level, "currentMana", "=", ret)
    return ret
end

function APLInterpreter:currentManaPercent(level)
    local ret = L.PowerPercent("player", SPELL_POWER_MANA)
    L.DebugLev(level, "currentManaPercent", "=", ret)
    return ret
end

function APLInterpreter:currentRage(level)
    local ret = UnitPower("player", SPELL_POWER_RAGE)
    L.DebugLev(level, "currentRage", "=", ret)
    return ret
end

function APLInterpreter:currentFocus(level)
    local ret = UnitPower("player", SPELL_POWER_FOCUS)
    L.DebugLev(level, "currentFocus", "=", ret)
    return ret
end

function APLInterpreter:currentEnergy(level)
    local ret = UnitPower("player", SPELL_POWER_ENERGY)
    L.DebugLev(level, "currentEnergy", "=", ret)
    return ret
end

function APLInterpreter:currentComboPoints(level)
    local ret = GetComboPoints("player", "target")
    L.DebugLev(level, "currentComboPoints", "=", ret)
    return ret
end

function APLInterpreter:unitIsMoving(level)
    local threshold = 0.01
    local ret = threshold < GetUnitSpeed("player")
    L.DebugLev(level, "unitIsMoving", "=", ret)
end

---@diagnostic disable-next-line: deprecated
L.UnitAura = _G["UnitAura"]
if L.UnitAura == nil then
    L.UnitAura = function(unit, i, filter)
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not auraData then
            return nil;
        end
        return AuraUtil.UnpackAuraData(auraData)
    end
end

function APLInterpreter:generateAuraCache(unit)
    if self.cacheAura[unit] then
        return
    end
    local cache = {}
    for _, filter in ipairs( {"HELPFUL", "HARMFUL"} ) do
        for i = 1, 255 do
            local name, _, _, _, _, expiration, _, _, _, spellId = L.UnitAura(unit, i, filter)
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

local UnitMap = {
    Player = "player",
    Target = "target",
    Pet = "pet",
    Self = "player", --??
    CurrentTarget = "target",
    AllPlayers = "??", --??
    AllTargets = "??", --??
}

function L.UnitMap(aplUnit, default)
    local unit = default
    if aplUnit then
        unit = UnitMap[aplUnit]
    end
    return unit
end

function APLInterpreter:auraIsActive(level, vals)
    local unit = L.UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    self:generateAuraCache(unit)
    local ret = self.cacheAura[unit][spellId] ~= nil
    L.DebugLev(level, "auraIsActive", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:dotIsActive(level, vals)
    local unit = L.UnitMap(vals.sourceUnit and vals.sourceUnit.type, "target")
    local spellId = vals.spellId.spellId
    self:generateAuraCache(unit)
    local ret = self.cacheAura[unit][spellId] or 0
    L.DebugLev(level, "dotIsActive", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:auraRemainingTime(level, vals)
    local unit = L.UnitMap(vals.sourceUnit and vals.sourceUnit.type, "player")
    local spellId = vals.auraId.spellId
    self:generateAuraCache(unit)
    local ret = self.cacheAura[unit][spellId] or 0
    L.DebugLev(level, "auraRemainingTime", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:dotRemainingTime(level, vals)
    local unit = L.UnitMap(vals.sourceUnit and vals.sourceUnit.type, "target")
    local spellId = vals.spellId.spellId
    self:generateAuraCache(unit)
    local ret = self.cacheAura[unit][spellId] ~= nil
    L.DebugLev(level, "dotRemainingTime", unit, spellId, "=", ret)
    return ret
end

function APLInterpreter:GetSpellCooldownNoCache(spellId)
    local ret = 0
    local start, duration = GetSpellCooldown(spellId)
    if 0 < start and 0 < duration then
        ret = start + duration - self.time
    end
    return ret
end

function APLInterpreter:GetSpellCooldown(spellId)
    local ret = 0
    if self.cacheSpells[spellId] then
        return self.cacheSpells[spellId]
    else
        ret = self:GetSpellCooldownNoCache(spellId)
        self.cacheSpells[spellId] = ret
    end
    return ret
end

function APLInterpreter:IsSpellReady(spellId)
    return self:GetSpellCooldown(spellId) <= self.gcd
end

function APLInterpreter:spellTimeToready(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self:GetSpellCooldown(spellId)
    L.DebugLev(level, "spellTimeToready", spellId, "=", ret)
    return ret
end

function APLInterpreter:spellIsReady(level, vals)
    local spellId = vals.spellId.spellId
    local ret = self:IsSpellReady(spellId)
    L.DebugLev(level, "spellIsReady", spellId, "=", ret)
    return ret
end

function APLInterpreter:currentTime(level)
    -- TODO: implement
    local ret = 0
    L.DebugLev(level, "currentTime", "=", ret)
end

function APLInterpreter:currentTimePercent(level)
    -- rough estimate based on health
    local ret = 1.0 - L.HealthPercent("target")
    L.DebugLev(level, "currentTimePercent", "=", ret)
    return ret
end

function APLInterpreter:remainingTime(level)
    -- rough estimate for 3 minute fight
    local ret = L.HealthPercent("target") * 3 * 60
    L.DebugLev(level, "remainingTime", "=", ret)
    return ret
end

function APLInterpreter:remainingTimePercent(level)
    -- rough estimate based on health
    local ret = L.HealthPercent("target")
    L.DebugLev(level, "remainingTimePercent", "=", ret)
    return ret
end

function L.IsExecutePhase(key)
    if key == "E90" then
        return 90 < L.HealthPercent("target")
    else
        local pct = tonumber(key:sub(2))
        return L.HealthPercent("target") <= pct
    end
end

function APLInterpreter:isExecutePhase(level, vals)
    local ret = L.IsExecutePhase(vals.threshold)
    L.DebugLev(level, "IsExecutePhase", "=", ret)
    return ret
end

function L.GetNumTargetsNearby()
    local num = 0
    local nameplates = C_NamePlate.GetNamePlates()
    for i=1,#nameplates 
    do 
        local unit = nameplates[i].namePlateUnitToken
        if UnitCanAttack("player", unit) and L.CheckRange(unit, 8, "<=")
        then
            num = num + 1
        end
    end
    return num
end

function L.CheckRange(unit, range, operator)
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

function APLInterpreter:numberTargets(level)
    local ret = L.GetNumTargetsNearby()
    L.DebugLev(level, "numberTargets", "=", ret)
    return ret
end

function APLInterpreter:frontOfTarget(level)
    local ret = false
    -- TODO: possible?
    L.DebugLev(level, "frontOfTarget", "=", ret)
    return ret
end

function APLInterpreter:bossSpellIsCasting(level)
    -- TODO: implement
    local ret = false
    L.DebugLev(level, "bossSpellIsCasting", "=", ret)
end

function APLInterpreter:bossSpellTimeToReady(level)
    -- TODO: possible? dbm?
    local ret = 0
    L.DebugLev(level, "bossSpellTimeToReady", "=", ret)
end

function APLInterpreter:gcdTimeToReady(level)
    local ret = self.gcd
    L.DebugLev(level, "gcdTimeToReady", "=", ret)
end

function APLInterpreter:gcdIsReady(level)
    local ret = self.gcd <= 0
    L.DebugLev(level, "gcdIsReady", "=", ret)
end
