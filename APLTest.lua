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



local LibCrypto = LibStub("LibCrypto-1.0")
local LibParse = LibStub("LibParse")

local bundle = LibParse:JSONDecode([[
{
	"version": 1,
	"pk": [171, 219, 11, 179, 118, 121, 211, 18, 151, 0, 15, 25, 75, 191, 17, 9, 66, 158, 201, 200, 190, 104, 206, 44, 240, 246, 141, 19, 0, 140, 119, 89],
	"nonce": [224, 234, 50, 10, 203, 243, 77, 113, 139, 53, 167, 187, 144, 16, 18, 184, 75, 49, 163, 14, 102, 105, 185, 33, 135, 243, 5, 24, 81, 236, 44, 126],
	"encrypted": "LEcYBqSBDCKZQ1Z9f6f8uOYdoJ84ODQliHOvwKuD6tGYPLDJnC+GyWkVXa2pt7bxCMpIbHoJf5MUI34oGFwCirF5vj2rn4yJNAe/3Zr3PqDzW4IAJEpOf2sTLR6XB8wC2F4kX/pxNu4YEVK0K/uQoFNDTrthmYLSv6nui2myt49OriT39ebXKeX/2CQBSl4p"
}
]])

local pk = LibCrypto.table_to_zero_indexed(bundle.pk)
local esk = LibCrypto.table_to_zero_indexed(bundle.nonce)
local cyphertext = LibCrypto.Base64.decode(bundle.encrypted)
local key = LibCrypto.X25519.get_shared_key(esk, pk)
local plaintext = LibCrypto.AES.ECB_256(LibCrypto.AES.decrypt, key, cyphertext)
local dict = LibParse:JSONDecode(plaintext)

DevTools_Dump(dict)


--[[


keep sk, send pk + esk to receiver, discard epk
use the 32 bytes shared key as aes key to encrypt/decrypt
{
	version: 1,
	pk: [0x00, 0xff, ...], -- pk (TODO: should bake into DRM? and use only a key?)
	nonce: [0x00, 0xff, ...], -- esk
	encrypted: "Base64Data/==" -- json data from below in b64
}

{
	license: {
		character: "name", -- licensed character, nil for any
		realm: "realm", -- licensed realm, nil for any
		valid: 1726057531, -- validity timestamp, nil for any
	},
	data: {any: 1}
}
]]--