# `verifier/js/` — reference verifier

WebCrypto only. No dependencies, nothing to install. Node 18 or newer.

```bash
node verify.mjs 1730-emission.jws
node verify.mjs https://.../2026/08/29/1730-emission.jws <public-key-hex>
```

Without the key it checks everything except the signature and says so. The public key for a `kid`
comes from [`../../keys/history.json`](../../keys/history.json).

## What it answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed — no key, no network, no Ed25519 |

**The third one is not a failure.** "I cannot check" and "this is false" are different answers.

## In a browser

`derive()`, `deriveBlock()` and `Stream` run unchanged: they only use `crypto.subtle`. The single
Node-specific piece is `readSource()`, which falls back to `fetch` for URLs anyway.

Ed25519 in WebCrypto is recent. If the runtime does not have it the verifier says `UNVERIFIABLE`
for the signature instead of guessing.

## What it does not check, on purpose

It does not verify drand's **BLS signature**: that needs a pairing library, and this file has no
dependencies. It asks drand for the round instead — the proof that the number is theirs comes from
them. The round travels whole inside the file if you want to add the check yourself.

## Reuse it

That is what it is for. Copy `Stream`, `deriveBlock` and `derive` into your project and you have the
numbers. The rest is plumbing.

Read [`../../spec/README.md`](../../spec/README.md) first: the three details that break every
reimplementation are listed there.
