local ADDON, T = ...
local L = {}

local LAPL = LibStub("LibAPL-1.0")

_G["SLASH_"..ADDON.."1"] = "/apl"

local function ProcessCommand(msg)
	local _, _, cmd, args = string.find(msg or "", "%s?(%w+)%s?(.*)")
	local cmdlower = strlower(cmd or "")
	if not cmd or cmdlower == "debug" -- or cmdlower == ""
	then
		L.DoUpdate(nil, 1)
	end
end

local function ExtractFirstKey(tab)
    for k,_ in pairs(tab) do
        return tostring(k)
    end
    return "<empty>"
end

local function Init()
	print(ADDON.." Init()")

	local f = CreateFrame("Frame",nil,UIParent)
	f:SetWidth(48)
	f:SetHeight(48)
	f:SetPoint("CENTER",0,-96)
	f.text = f:CreateFontString(nil,"ARTWORK") 
	f.text:SetFont("Fonts\\ARIALN.ttf", 14, "OUTLINE")
	f.text:SetPoint("CENTER",0,-32)
	f.text:SetText("")
	f.texture = f:CreateTexture(nil, "BACKGROUND")
	f.texture:SetAllPoints()
	f:Show()

	local externals = {
		["somefunc"] = function() return false end,
		["otherfunc"] = function() return 3.333 end
	}
	local runner = LAPL:New(T.APL.Rogue_Combat, nil, externals, true)

	L.DrawSpell = function(self, spellId)
		if spellId == "OtherActionPotion" then
			spellId = 79633 -- TODO: configure?
		end
		local spellName, _, spellIcon = GetSpellInfo(spellId)
		f.texture:Show()
		f.texture:SetTexture(spellIcon)
		f.text:SetText(spellName)
	end
	
	L.DrawAction = function(self, ...)
		for _,action in ipairs({...}) do
			if action then
				if action.castSpell then
					local spellId = action.castSpell.spellId.spellId or action.castSpell.spellId.otherId
					L:DrawSpell(spellId)
				elseif action.strictSequence or action.sequence then
					L:DrawAction(runner:SequenceNext())
				elseif action.prepull then
					L:DrawAction(action.prepull.action) -- TODO: render multiple actions
				else
					if action ~= nil then
						local key = ExtractFirstKey(action)
						print("Unknown Action:", key)
						f.text:SetText(key)
					end
					f.texture:Hide()
				end
			end
		end
	end

	local timeElapsed = 0
	L.DoUpdate = function(self, elapsed)
		timeElapsed = timeElapsed + elapsed
		if timeElapsed > 0.1 then
			timeElapsed = 0
			if UnitExists("target") then
				L:DrawAction(runner:Run())
			else
				f.texture:Hide()
				f.text:SetText("")
			end
		end
	end


	--DevTools_Dump(variable)

	f:HookScript("OnUpdate", L.DoUpdate )

end

local function OnEvent(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		self:UnregisterEvent("ADDON_LOADED")
		SlashCmdList[ADDON] = ProcessCommand
		Init()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)

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
    f.text:SetText(L.DebugFrameText)
    local debugText = ""

	local function DumpVar(arg, name)
		name = name or "debug"
		DevTool.MainWindow:Show()
		DevTool:ClearAllData()
		DevTool:AddData(arg, name)
		DevTool:UpdateMainTableUI()
	end

	local function DebugClear()
		debugText = ""
	end

	local function Debug(...)
		for _,v in ipairs({...}) do
			if type(v) == "number" and (v % 1) ~= 0 then
				debugText= debugText .. string.format("%.4f", v) .. " "
			else
				debugText= debugText .. tostring(v) .. " "
			end
		end
		debugText = debugText .. "\n"
		f.text:SetText(debugText)
	end

	LAPL:AttachDebugger(DebugClear, Debug, DumpVar)
end

local LibDRM = LibStub("LibDRM-1.0")

--[[
import json
import datetime
from LibDRM import generate_bundle
sk = bytes.fromhex("65916d34c51d45a839d8bce84f0db253aeb4e46a73f6a2ff93fcc31bad4c8b47")
print(json.dumps( generate_bundle(sk, {"some": "data"}, character="Deathbaron", realm="Golemagg", expires=datetime.datetime(2024, 10, 10).timestamp(), key_owner="Test") ))
]]--

local json = [[
{
	"version": 1,
	"pk": "Test",
	"nonce": [112, 255, 97, 139, 45, 15, 145, 38, 96, 191, 101, 155, 30, 220, 241, 252, 89, 204, 99, 67, 108, 151, 62, 88, 75, 50, 225, 3, 20, 188, 4, 103],
	"encrypted": "/3MEe6k+s3eY2sQddNHMGvtFRZVM/sFg3ccChUpgrRCP0xnUHQ/xmtcPcDGWeCDWsuJOHEYEtbIVRHhRV4XSQ43oRFhHMpSG4qT+H3C8YNyS/UleHT5oyMxqXqWS1A7KitFdj+XS4KPs0UVy1Au6DfGUW+VyMndQqOMipaRHkrc="
}
]]

DevTools_Dump(LibDRM.Load(json))
