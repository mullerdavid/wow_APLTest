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

local function Init()
	print(ADDON.." Init()")

	local f = CreateFrame("Frame",nil,UIParent)
	f:SetWidth(64)
	f:SetHeight(64)
	f:SetPoint("CENTER",0,-96)
	f.text = f:CreateFontString(nil,"ARTWORK") 
	f.text:SetFont("Fonts\\ARIALN.ttf", 14, "OUTLINE")
	f.text:SetPoint("CENTER",0,-40)
	f.text:SetText("")
	f.texture = f:CreateTexture(nil, "BACKGROUND")
	f.texture:SetAllPoints()
	f:Show()

	local runner = LAPL:New(T.APL.Rogue_Combat)
	local timeElapsed = 0
	L.DoUpdate = function(self, elapsed)
		timeElapsed = timeElapsed + elapsed
		if timeElapsed > 0.1 then
			timeElapsed = 0
			if UnitExists("target") then
				local action, params = runner:Run()
				if action == "castSpell" then
					local spellId = params
					local spellName, _, spellIcon = GetSpellInfo(spellId)
					f.texture:Show()
					f.texture:SetTexture(spellIcon)
					f.text:SetText(spellName)
				else
					f.texture:Hide()
					f.text:SetText(action)
				end
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
	if event == "ADDON_LOADED" and arg1 == ADDON
	then
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
