--[[
TODO:
LibAPL
	implement missing methods
	aura/dot source? Datastore?
	caching compute heavy stuff
	precompiled version instead interpreted if speed if issue
]]--


local ADDON, T = ...
local L = {}

local LibCrypto = LibStub("LibCrypto-1.0")
local LibDRM = LibStub("LibDRM-1.0")
local LAPL = LibStub("LibAPL-1.0")

APLTestSavedVariablesPerCharacter = APLTestSavedVariablesPerCharacter or {}

_G["SLASH_"..ADDON.."1"] = "/apl"

local SetDebugger = function() end

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

	SetDebugger = function(enable)
		if enable then
			LAPL:AttachDebugger(DebugClear, Debug, DumpVar)
		else
			LAPL:DetachDebugger()
			DebugClear()
			Debug()
		end
	end
end

local function ToggleDebugger()
	APLTestSavedVariablesPerCharacter.debug = not APLTestSavedVariablesPerCharacter.debug
	SetDebugger(APLTestSavedVariablesPerCharacter.debug)
end

local function ProcessCommand(msg)
	local _, _, cmd, args = string.find(msg or "", "%s?(%w+)%s?(.*)")
	local cmdlower = strlower(cmd or "")
	if not cmd or cmdlower == "import" or cmdlower == "" then
		APLImport:Show()
	elseif not cmd or cmdlower == "debug" then
		if ToggleDebugger then
			ToggleDebugger()
		end
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

	local runner = nil

	L.LoadAPL = function(str)
		--[[
			import json
			import datetime
			from LibDRM import generate_bundle
			sk = bytes.fromhex("65916d34c51d45a839d8bce84f0db253aeb4e46a73f6a2ff93fcc31bad4c8b47")
			print(json.dumps( generate_bundle(sk, {"some": "data"}, character="Deathbaron", realm="Golemagg", expires=datetime.datetime(2024, 10, 10).timestamp(), key_owner="Test") ))
		]]--
		--[[
			{
				"version": 1,
				"pk": "Test",
				"nonce": [112, 255, 97, 139, 45, 15, 145, 38, 96, 191, 101, 155, 30, 220, 241, 252, 89, 204, 99, 67, 108, 151, 62, 88, 75, 50, 225, 3, 20, 188, 4, 103],
				"encrypted": "/3MEe6k+s3eY2sQddNHMGvtFRZVM/sFg3ccChUpgrRCP0xnUHQ/xmtcPcDGWeCDWsuJOHEYEtbIVRHhRV4XSQ43oRFhHMpSG4qT+H3C8YNyS/UleHT5oyMxqXqWS1A7KitFdj+XS4KPs0UVy1Au6DfGUW+VyMndQqOMipaRHkrc="
			}
		]]--

		if not str then
			return false
		end
		local apl_data = nil
		pcall(function ()
			apl_data = LibCrypto.JSON.decode(str)
		end)
		if not apl_data then
			print("Invalid JSON")
			return false
		end
		if apl_data.version and apl_data.encrypted then
			apl_data = LibDRM.Load(apl_data)
		end
		
		local externals = {
			["somefunc"] = function() return false end,
			["otherfunc"] = function() return 3.333 end
		}

		local status, err = pcall(function ()
			runner = LAPL:New(apl_data, nil, externals, true)
		end)
		if not status then
			print(err)
			return false
		end
		

		return true
	end

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
					if runner then
						L:DrawAction(runner:SequenceNext())
					end
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
			if UnitExists("target") and runner then
				L:DrawAction(runner:Run())
			else
				f.texture:Hide()
				f.text:SetText("")
			end
		end
	end

	f:HookScript("OnUpdate", L.DoUpdate )

	APLImport.ScriptOnShow = function(self)
		if APLTestSavedVariablesPerCharacter.apl then
			self.ScrollBox.EditBox:SetText(APLTestSavedVariablesPerCharacter.apl)
		end
	end

	APLImport.ScriptOnOkClick = function(self)
		local data = self.ScrollBox.EditBox:GetText()
		if L.LoadAPL(data) then
			APLTestSavedVariablesPerCharacter.apl = data
		end
	end

	L.LoadAPL(APLTestSavedVariablesPerCharacter.apl)
	SetDebugger(APLTestSavedVariablesPerCharacter.debug)
	--DevTools_Dump(variable)
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
