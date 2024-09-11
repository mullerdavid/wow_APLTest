from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend
from base64 import b64encode
from json import dumps

def print_as_lua_table(lst):
    print("{"+",".join(["0x%02x" % b for b in lst])+"}")

def print_hex(lst):
    print(",".join(["%02x" % b for b in lst]))
    
def convert_bytes_to_array(inp):
    return [int(b) for b in inp]

def generate_keypair():
    sk = X25519PrivateKey.generate()
    pk = sk.public_key()
    return sk, pk

sk = X25519PrivateKey.from_private_bytes(bytes([101, 145, 109, 52, 197, 29, 69, 168, 57, 216, 188, 232, 79, 13, 178, 83, 174, 180, 228, 106, 115, 246, 162, 255, 147, 252, 195, 27, 173, 76, 139, 71])) # TODO: test key!
pk = sk.public_key()
esk = X25519PrivateKey.generate()
epk = esk.public_key()
# print_as_lua_table(sk.private_bytes_raw())
# print_as_lua_table(pk.public_bytes_raw())
# print_as_lua_table(esk.private_bytes_raw())
# print_as_lua_table(epk.public_bytes_raw())

shared_key = sk.exchange(epk)
# print_hex(shared_key)

encryptor = Cipher(algorithms.AES(shared_key), modes.ECB(), default_backend()).encryptor()


lic = {
    "license": {
		"character": "Deathbaron",
		"realm": "Golemagg",
		"valid": 1726057531,
	},
    "data": {
        "something": "other",
        "testing": 1234
    }
}

lic_str = dumps(lic)
lic_str = lic_str.ljust(len(lic_str) + (16 - len(lic_str) % 16))
lic_enc = encryptor.update(lic_str.encode("latin1")) + encryptor.finalize()

bundle = {
	"version": 1,
	"pk": convert_bytes_to_array(pk.public_bytes_raw()),
	"nonce": convert_bytes_to_array(esk.private_bytes_raw()),
	"encrypted": b64encode(lic_enc).decode("latin1")
}   

print(dumps(bundle))