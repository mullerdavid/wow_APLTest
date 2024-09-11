--[[
Very basic DRM implementation. Can be easily bypassed, as there is no porper PKI infrastructure.
See LibDRM.py for example generation.
]]--

--region LibStub

local LIB_VERSION_MAJOR, LIB_VERSION_MINOR = "LibDRM-1.0", 1

local LibDRM = LibStub:NewLibrary(LIB_VERSION_MAJOR, LIB_VERSION_MINOR)
if not LibDRM then
    return
end

local LibCrypto = LibStub("LibCrypto-1.0")
local LibParse = LibStub("LibParse")

--#endregion

--#region Public Keys

local PUBLIC_KEYS = {
	["Test"] = {171, 219, 11, 179, 118, 121, 211, 18, 151, 0, 15, 25, 75, 191, 17, 9, 66, 158, 201, 200, 190, 104, 206, 44, 240, 246, 141, 19, 0, 140, 119, 89}
}

--#endregion

--#region LibDRM

local CACHE = {}

local function CheckValidity(license)
    if license.character and license.character ~= UnitName("player") then
        return false, "Character mismatch"
    end
    if license.realm and license.realm ~= GetRealmName() then
        return false, "Realm mismatch"
    end
    if license.expires and license.expires < GetServerTime() then
        return false, "License expired"
    end
    return true
end

function LibDRM.Load(json_or_table, identifier)
    if identifier and CACHE[identifier] then
        return CACHE[identifier]
    end
    local ret
    local status, err = pcall(function ()
        local bundle = (type(json_or_table) == "table") and json_or_table or LibParse:JSONDecode(json_or_table)
        local pk = LibCrypto.table_to_zero_indexed((type(bundle.pk) == "table") and bundle.pk or PUBLIC_KEYS[bundle.pk])
        local esk = LibCrypto.table_to_zero_indexed(bundle.nonce)
        local cyphertext = LibCrypto.Base64.decode(bundle.encrypted)
        local key = LibCrypto.X25519.get_shared_key(esk, pk)
        local plaintext = LibCrypto.AES.ECB_256(LibCrypto.AES.decrypt, key, cyphertext)
        local dict = LibParse:JSONDecode(plaintext)
        local valid, reason = CheckValidity(dict.license)
        if valid then
            ret = dict
        else
            print("License is invalid:", reason)
        end
    end)
    if not status then
        print(err)
    else
        if identifier then
            CACHE[identifier] = ret
        end
        return ret
    end
end
