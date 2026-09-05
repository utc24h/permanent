# `verifier/py/` — reference verifier

```bash
python3 verify.py 1730-emission.jws
python3 verify.py https://.../2026/08/29/1730-emission.jws <public-key-hex>
```

Without the key it checks everything except the signature and says so. The public key for a `kid`
comes from [`../../keys/history.json`](../../keys/history.json).

## Dependency

| | |
|---|---|
| Hashing, HKDF, derivation | standard library — `hashlib`, `hmac` |
| **Ed25519 signature** | **`cryptography`** · `pip install cryptography` · <https://pypi.org/project/cryptography/> |

`cryptography` is maintained by the Python Cryptographic Authority and is backed by OpenSSL. Without
it the verifier answers `UNVERIFIABLE` for the signature instead of guessing; everything else still
runs.

## What it answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed |

## What it does not check, on purpose

It does not verify drand's **BLS signature**: that needs a pairing library, which is a very
different kind of dependency. It asks drand for the round instead — the proof that the number is
theirs comes from them. The round travels whole inside the file if you want to add the check.

## Reuse it

Copy `Stream`, `derive_block` and `derive` into your project and you have the numbers. The rest is
plumbing.

Read [`../../spec/README.md`](../../spec/README.md) first: the three details that break every
reimplementation are listed there.
