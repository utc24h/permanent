# `verifier/delphi/` — reference verifier

```
dcc64 verify.dpr
verify.exe 1730-emission.jws [public-key-hex]
```

It reads a file, not a URL:

```
curl -s https://.../2026/08/29/1730-emission.jws -o e.jws && verify e.jws
```

The public key for a `kid` comes from [`../../keys/history.json`](../../keys/history.json).

## Dependencies

| | |
|---|---|
| SHA-256, HMAC, base64url, JSON | **the standard library** — `System.Hash`, `System.NetEncoding`, `System.JSON` |
| **Ed25519** | `libcrypto-3-x64.dll` · <https://openssl-library.org> — next to the executable |

The library is loaded at run time on purpose: without it the verifier answers `UNVERIFIABLE` for
the signature and still checks everything else. A missing DLL is not a reason to answer "false".

Compiles for Windows and Linux. On Linux it looks for `libcrypto.so.3`.

## Two things that will bite you

**`SHA256` is a function name and an enum value at the same time.** Pascal is case-insensitive, so a
function called `Sha256` shadows `THashSHA2.TSHA2Version.SHA256` and the compiler says *"Not enough
actual parameters"*, which points nowhere. Qualify the enum.

**`THashSHA2.GetHashBytes` does not accept `TBytes`** — only `string` or `TStream`. Passing a string
would mean choosing an encoding, and rule **R2** says hashes go over the **bytes**. Use the instance
API: `Create` · `Update` · `HashAsBytes`.

## What it answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed |

## What it does not check, on purpose

It does not fetch the drand round, and it does not verify drand's **BLS signature** — that needs a
pairing library. Compare `round.randomness` against `https://api.drand.sh/public/<round>` yourself;
the round travels whole inside the file.

## Reuse it

Copy `TStream_`, `DeriveBlock` and `Hkdf` into your project and you have the numbers.

Read [`../../spec/README.md`](../../spec/README.md) first: the three details that break every
reimplementation are listed there.
