#!/usr/bin/env python3
"""Reference verifier for the randomness beacon.

    python3 verify.py emission.jws
    python3 verify.py https://.../2026/08/29/1730-emission.jws <public-key-hex>

Hashing and derivation use the standard library only.

The Ed25519 signature needs one dependency:

    cryptography    pip install cryptography
                    https://pypi.org/project/cryptography/
                    Python Cryptographic Authority, backed by OpenSSL

Without it the verifier says UNVERIFIABLE for that check instead of guessing.
"""

import hashlib
import hmac
import json
import sys
import urllib.request
from base64 import urlsafe_b64decode

HKDF_BLOCK = 64
DRAND_RELAY = "https://drand.cloudflare.com"
HTTP_TIMEOUT = 20


# --- The byte stream -------------------------------------------------------


class Stream:
    def __init__(self, seed, public, context):
        self.seed = seed
        self.public = public
        self.context = context
        self.buf = b""
        self.pos = 0

    def next_byte(self):
        if self.pos >= len(self.buf):
            info = self.context + b"|" + str(len(self.buf)).encode()
            self.buf += hkdf(self.seed, self.public, info, HKDF_BLOCK)
        b = self.buf[self.pos]
        self.pos += 1
        return b

    def integer(self, limit):
        """Uniform value in [0,limit) with no modulo bias: values above the
        last whole multiple of limit are discarded and drawn again."""
        if limit <= 1:
            return 0

        width, space = 1, 256
        while space < limit:
            width += 1
            space *= 256
        cut = (space // limit) * limit

        while True:
            v = 0
            for _ in range(width):
                v = v * 256 + self.next_byte()
            if v < cut:
                return v % limit


def hkdf(ikm, salt, info, length):
    """HKDF-SHA256, RFC 5869, both stages."""
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()

    out, block, i = b"", b"", 1
    while len(out) < length:
        block = hmac.new(prk, block + info + bytes([i]), hashlib.sha256).digest()
        out += block
        i += 1
    return out[:length]


# --- Derivation ------------------------------------------------------------


def blocks_of(group, v):
    """A variant is published in one of two shapes, and this is the first thing
    a reimplementation gets wrong:

      - composite carries an explicit "blocks" array
      - every other group carries its parameters FLAT, and the mold is the
        GROUP NAME, not a field

    Two more traps in the flat shape: random_matrix carries rows/cols instead
    of count, and truncated_continuous publishes min/max already multiplied by
    scale.
    """
    if group == "composite":
        return v["blocks"]
    count = v["rows"] * v["cols"] if group == "random_matrix" else v.get("count", 1)
    return [{"mold": group, "count": count, "min": v["min"], "max": v["max"]}]


def derive(em, name, spec):
    seed = bytes.fromhex(em["seed"])
    public = bytes.fromhex(em["round"]["randomness"])
    base = f"{em['version']}|{name}|{em['drand_round']}"

    blocks = []
    for i, b in enumerate(spec):
        s = Stream(seed, public, f"{base}|b{i}".encode())
        blocks.append(derive_block(s, b))
    return shape(name, spec, blocks)


def derive_block(s, b):
    universe = b["max"] - b["min"] + 1
    if universe < 1:
        raise ValueError(f"empty universe [{b['min']}..{b['max']}]")
    count = b.get("count") or 1
    mold = b["mold"]

    if mold == "discrete_uniform":
        return [b["min"] + s.integer(universe)]

    if mold == "sample_without_replacement":
        if count > universe:
            raise ValueError(f"asks for {count} out of {universe}")
        return sorted(sample_without_replacement(s, universe, count, b["min"]))

    if mold == "permutation":
        if count > universe:
            raise ValueError(f"asks for {count} out of {universe}")
        return sample_without_replacement(s, universe, count, b["min"])

    if mold in ("uniform_vector_with_replacement", "random_matrix"):
        return [b["min"] + s.integer(universe) for _ in range(count)]

    # min and max already carry the scale, so the span is read straight off the
    # file. Multiplying again is the classic reimplementation bug.
    if mold == "truncated_continuous":
        return [b["min"] + s.integer(b["max"] - b["min"] + 1)]

    raise ValueError(f'unknown mold "{mold}"')


def sample_without_replacement(s, universe, count, minimum):
    """Draws k distinct values in the order they come out, with a partial
    Fisher-Yates over a sparse map."""
    moved, out = {}, []

    for i in range(count):
        j = i + s.integer(universe - i)
        vj = moved.get(j, j)
        vi = moved.get(i, i)
        moved[j], moved[i] = vi, vj
        out.append(minimum + vj)
    return out


def shape(name, spec, values):
    """Renders the result the way the file publishes it: a scalar, a list, a
    list of rows, or one list per block."""
    if len(spec) > 1:
        return values
    flat = values[0]
    mold = spec[0]["mold"]

    if mold in ("discrete_uniform", "truncated_continuous"):
        return flat[0]

    if mold == "random_matrix":
        rows, cols = dimensions(name, len(flat))
        return [flat[i * cols : (i + 1) * cols] for i in range(rows)]

    return flat


def dimensions(name, total):
    """Reads the matrix shape from the variant name, m-<rows>x<cols>."""
    import re

    m = re.fullmatch(r"m-(\d+)x(\d+)", name)
    if m:
        rows, cols = int(m.group(1)), int(m.group(2))
        if rows > 0 and cols > 0 and rows * cols == total:
            return rows, cols
    return 1, total


# --- Checks ----------------------------------------------------------------


def main():
    if len(sys.argv) < 2:
        print("usage: python3 verify.py <file.jws|url> [public-key-hex]")
        sys.exit(2)
    source = sys.argv[1]
    key_hex = sys.argv[2] if len(sys.argv) > 2 else None

    try:
        raw = read_source(source).strip()
    except Exception as e:
        unverifiable(f"cannot read the file: {e}")

    parts = raw.split(".")
    if len(parts) != 3:
        not_verified(f"expected 3 dot-separated parts, got {len(parts)}")
    header = json.loads(b64(parts[0]))
    em = json.loads(b64(parts[1]))

    print(
        f"file      : {em['type']} turn {em['utc_turn']}, "
        f"version {em['version']}, drand round {em['drand_round']}"
    )
    print(f"key id    : {header.get('kid')}")

    # 1. Signature, over the RAW text: re-serializing the JSON changes the
    # bytes and breaks a signature that is perfectly valid.
    if key_hex:
        try:
            from cryptography.exceptions import InvalidSignature
            from cryptography.hazmat.primitives.asymmetric.ed25519 import (
                Ed25519PublicKey,
            )
        except ImportError:
            unverifiable(
                "Ed25519 needs `cryptography`: pip install cryptography  "
                "(https://pypi.org/project/cryptography/)"
            )

        key = Ed25519PublicKey.from_public_bytes(bytes.fromhex(key_hex.strip()))
        signed = (parts[0] + "." + parts[1]).encode()
        try:
            key.verify(b64(parts[2]), signed)
        except InvalidSignature:
            not_verified("the Ed25519 signature does not verify")
        print("signature : OK")
    else:
        print("signature : SKIPPED, no public key given")

    # 2. The revealed seed must hash to what was committed.
    if hashlib.sha256(bytes.fromhex(em["seed"])).hexdigest() != em["seed_sha256"]:
        not_verified("SHA-256 of the seed does not match seed_sha256")
    print("seed      : OK, matches its own hash")

    # 3. The public value comes from drand, not from us. Ask them.
    try:
        body = read_source(f"{DRAND_RELAY}/public/{em['drand_round']}")
        if json.loads(body)["randomness"] != em["round"]["randomness"]:
            not_verified(f"drand round {em['drand_round']} carries a different randomness")
        print(f"drand     : OK, round {em['drand_round']} carries this randomness")
    except SystemExit:
        raise
    except Exception as e:
        print(f"drand     : SKIPPED, {e}")

    # 4. Every number, reproduced from the seed and the round.
    checked = failed = 0
    for group, variants in em["variants"].items():
        for name, v in variants.items():
            got = json.dumps(derive(em, name, blocks_of(group, v)), separators=(",", ":"))
            want = json.dumps(v["result"], separators=(",", ":"))
            if got != want:
                failed += 1
                print(f"  {name:<24} MISMATCH\n     expected {want}\n     computed {got}")
                continue
            checked += 1

    if failed:
        not_verified(f"{failed} of {checked + failed} variants do not reproduce")
    print(f"numbers   : OK, {checked} variants reproduced")

    print("\nVERIFIED")


# --- Plumbing --------------------------------------------------------------


def b64(s):
    return urlsafe_b64decode(s + "=" * (-len(s) % 4))


def read_source(source):
    if source.startswith(("http://", "https://")):
        # A User-Agent is required: the default one urllib sends is rejected
        # by some CDNs with a 403, drand's included.
        req = urllib.request.Request(source, headers={"User-Agent": "beacon-verifier"})
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as r:
            return r.read().decode()
    with open(source, encoding="utf-8") as fh:
        return fh.read()


def not_verified(message):
    print(f"\nNOT VERIFIED: {message}")
    sys.exit(1)


def unverifiable(message):
    print(f"\nUNVERIFIABLE: {message}")
    sys.exit(3)


if __name__ == "__main__":
    main()
