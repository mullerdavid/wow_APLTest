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

local sk, pk, esk, epk
if false then
    sk, pk = X25519.generate_keypair()
    esk, epk = X25519.generate_keypair()
elseif true then
    sk = LibCrypto.table_to_zero_indexed({0x38,0xb5,0x62,0x0d,0x2d,0x93,0x1a,0xe3,0x63,0x64,0xc6,0x33,0xf0,0x11,0x31,0x1f,0xc2,0x13,0x46,0x88,0x54,0xa7,0x9e,0x25,0x31,0xdf,0xc4,0x28,0x62,0x41,0x07,0x6d})
    pk = LibCrypto.table_to_zero_indexed({0xa3,0x05,0xe5,0x8f,0xa7,0x4d,0xc5,0x7e,0xa8,0x32,0xc8,0x1a,0x69,0x79,0xbe,0xf5,0xa8,0x97,0x64,0x06,0xa4,0x9e,0xb9,0x43,0xfb,0x97,0x95,0x33,0x5d,0x1f,0xf8,0x44})
    esk = LibCrypto.table_to_zero_indexed({0x98,0xb2,0x88,0x88,0xf8,0x3d,0xcf,0xc9,0x7b,0x9f,0xea,0x36,0x2a,0x3d,0x71,0x0c,0x08,0x73,0xc5,0xe2,0xb7,0x9e,0xb9,0xa7,0xd3,0xaf,0xb4,0xcc,0x40,0x2d,0x6a,0x54})
    epk = LibCrypto.table_to_zero_indexed({0x35,0x66,0x97,0xed,0x50,0x90,0x59,0xc6,0x18,0xad,0xec,0x42,0xc2,0x3d,0x8b,0xd4,0x0e,0x70,0xb4,0x43,0x14,0x63,0x77,0xe2,0xb0,0x62,0xfa,0xe7,0x0f,0xc5,0x4a,0x34})
else
    sk = LibCrypto.table_to_zero_indexed({0xf1,0xd2,0xae,0xa0,0xf9,0x52,0x50,0x58,0x1e,0x15,0x42,0x82,0x42,0x83,0x02,0x1a,0x3c,0x47,0x54,0x30,0x11,0x92,0x69,0x36,0x89,0x3a,0xdd,0x25,0xf9,0x3c,0xa9,0x58})
    pk = LibCrypto.table_to_zero_indexed({0x19,0x68,0x35,0xd8,0x9e,0xc2,0x29,0xf0,0xd8,0x1b,0x66,0x91,0xa5,0x2c,0x37,0x5a,0xeb,0xd3,0xce,0xd6,0x73,0x97,0x64,0xbe,0xfe,0x6a,0x80,0xed,0xa1,0x85,0xaa,0x20})
    esk = LibCrypto.table_to_zero_indexed({0x30,0x0b,0xa6,0x9a,0xa8,0x3f,0xd2,0x3d,0xeb,0x8e,0xa7,0x61,0xeb,0x7d,0x0e,0xbf,0x64,0x03,0x41,0x84,0xbb,0x0f,0xe9,0x56,0x6c,0x0d,0xed,0xfe,0xd0,0xf6,0x05,0x34})
    epk = LibCrypto.table_to_zero_indexed({0x03,0xdd,0x5f,0x8f,0x34,0x94,0x1a,0x90,0x30,0x2b,0x94,0x3c,0x5d,0xeb,0x1e,0x75,0xfe,0xbe,0xef,0xfd,0xe1,0x70,0x93,0x79,0x32,0xa7,0x56,0xeb,0x4c,0x2c,0xc5,0x28})
    -- 3410e8c90f834a02ca 2e436e676e16bbf3 b92c3d5af5b9551e ffbbf06c2e2277
end

print("----")
LibCrypto.print_hex_table(sk)
LibCrypto.print_hex_table(pk)
LibCrypto.print_hex_table(esk)
LibCrypto.print_hex_table(epk)
print("----")
LibCrypto.print_hex_table(X25519.get_shared_key(sk, epk))
print("----")
local shared_secret = X25519.get_shared_key(esk, pk)
LibCrypto.print_hex_table(shared_secret)
print("----")


local key = shared_secret
--key = table_to_zero_indexed({0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f})
local plaintext = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur vestibulum tristique ipsum, at ultrices erat sagittis eu. Quisque egestas sollicitudin pellentesque. Integer non nisi ut odio sollicitudin scelerisque quis vel quam. Nullam suscipit metus a venenatis iaculis. Nam tristique finibus ex, in malesuada sem. Ut nec neque in turpis consectetur ullamcorper sit amet sed mauris. In imperdiet semper dignissim. Nullam at nibh bibendum, tincidunt tellus eu, ultricies risus. Duis sodales metus vitae erat commodo iaculis. Integer porttitor egestas venenatis. "
-- plaintext = Base64.decode('ABEiM0RVZneImaq7zN3u/w==') -- 00112233445566778899aabbccddeeff
local cyphertext = LibCrypto.AES.ECB_256(LibCrypto.AES.encrypt, key, plaintext)
local b64_cyphertext = LibCrypto.Base64.encode(cyphertext)
local cyphertext2 = LibCrypto.Base64.decode(b64_cyphertext)
local plaintext2 = LibCrypto.AES.ECB_256(LibCrypto.AES.decrypt, key, cyphertext2)


print("plaintext:", #plaintext, plaintext)
print("cyphertext:", #cyphertext, b64_cyphertext)
print("plaintext:", #plaintext2, plaintext2)

--[[


keep sk, send pk + esk to receiver, discard epk
use the 32 bytes shared key as aes key to encrypt/decrypt
--------------

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

def print_as_lua_table(lst):
    print("{"+",".join(["0x%02x" % b for b in lst])+"}")
    
def print_hex(lst):
    print(",".join(["%02x" % b for b in lst]))

def generate_keypair():
    sk = X25519PrivateKey.generate()
    pk = sk.public_key()
    return sk, pk

sk, pk = generate_keypair()
esk, epk = generate_keypair()
print_as_lua_table(sk.private_bytes_raw())
print_as_lua_table(pk.public_bytes_raw())
print_as_lua_table(esk.private_bytes_raw())
print_as_lua_table(epk.public_bytes_raw())

shared_key = sk.exchange(epk)
print_hex(shared_key)
]]--