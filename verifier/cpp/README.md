# `verifier/cpp/` — reference verifier

```bash
g++ -std=c++17 -O2 verify.cpp -lcrypto -o verify
./verify 1730-emission.jws [public-key-hex]
```

It reads a file, not a URL:

```bash
curl -s https://.../2026/08/29/1730-emission.jws -o e.jws && ./verify e.jws
```

The public key for a `kid` comes from [`../../keys/history.json`](../../keys/history.json).

## Dependencies

| | |
|---|---|
| **OpenSSL** (`libcrypto`) | SHA-256, HMAC and Ed25519 · <https://openssl-library.org> · `apt install libssl-dev` |
| **nlohmann/json** | header only · <https://github.com/nlohmann/json> · `apt install nlohmann-json3-dev` |

Both are packaged on every distribution and neither is going anywhere. Hand-rolling a JSON parser
or a hash inside a verifier is how a verifier ends up accusing an honest file.

## What it answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed |

## What it does not check, on purpose

It does not fetch the drand round — it has no HTTP client and does not need one for the derivation.
Compare `round.randomness` against `https://api.drand.sh/public/<round>` yourself; the round travels
whole inside the file.

It does not verify drand's **BLS signature** either: that needs a pairing library, a very different
kind of dependency.

## Reuse it

Copy `Stream`, `deriveBlock` and the loop in `main` into your project and you have the numbers.

Read [`../../spec/README.md`](../../spec/README.md) first: the three details that break every
reimplementation are listed there.
