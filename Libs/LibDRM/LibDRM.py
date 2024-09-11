#!/bin/env python3 
# pip install cryptography

import sys
import json
import base64

from typing import Optional
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

def print_hex(lst: list):
    print(",".join(["%02x" % b for b in lst]))
    
def convert_bytes_to_array(inp: bytes) -> list:
    return [int(b) for b in inp]
    
def generate_bundle(sk_bytes: bytes, data: dict, character: Optional[str]=None, realm: Optional[str]=None, expires: Optional[float]=None, key_owner: Optional[str]=None) -> dict:
    sk = X25519PrivateKey.from_private_bytes(sk_bytes)
    pk = sk.public_key()
    esk = X25519PrivateKey.generate()
    epk = esk.public_key()
    shared_key = sk.exchange(epk)
    encryptor = Cipher(algorithms.AES(shared_key), modes.ECB(), default_backend()).encryptor()

    lic = {
        "license": {
            "character": character,
            "realm": realm,
            "expires": expires,
        },
        "data": data
    }

    lic_str = json.dumps(lic)
    lic_pad = lic_str.ljust(len(lic_str) + (16 - len(lic_str) % 16))
    lic_enc = encryptor.update(lic_pad.encode("latin1")) + encryptor.finalize()

    bundle = {
        "version": 1,
        "pk": key_owner if key_owner else convert_bytes_to_array(pk.public_bytes_raw()),
        "nonce": convert_bytes_to_array(esk.private_bytes_raw()),
        "encrypted": base64.b64encode(lic_enc).decode("latin1")
    }  

    return bundle 

def usage():
    executable = sys.argv[0]
    print(f"Usage: {executable} <secret_key_hex> [input_json]")
    print(f"  secret_key_hex: 32 bytes random key in hex")
    print(f"  input_json: optional json string to convert, reading json from stdin if not specified")
    print(f"""Example: {executable} 65916d34c51d45a839d8bce84f0db253aeb4e46a73f6a2ff93fcc31bad4c8b47 '{{"json": "data"}}'""")

def main():
    if (len(sys.argv) < 2):
        usage()
    else:
        sk = bytes.fromhex(sys.argv[1])
        data = None
        if (2 < len(sys.argv)):
            data = json.loads(sys.argv[2])
        else:
            data = json.load(sys.stdin)
        b = generate_bundle(sk, data)
        print(json.dumps(b))

if __name__ == "__main__":
    main()

'''
Generate X25519 sk, pk, esk, epk. 
Keep sk, send pk + esk to receiver, discard epk.
Use the 32 bytes shared key as AES key to encrypt the data.

data:
{
	"license": {
		"character": "name", -- licensed character, nil for any
		"realm": "realm", -- licensed realm, nil for any
		"valid": 1726057531, -- validity timestamp, nil for any
	},
	"data": {"any": 1}
}

final:
{
	"version": 1, -- fixed version string
	"pk": [0x00, 0xff, ...], -- pk
	"nonce": [0x00, 0xff, ...], -- esk
	"encrypted": "Base64Data/==" -- json data from above in b64
}
'''
