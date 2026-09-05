# `verifier/go/` — reference verifier

Standard library only. Nothing to install, nothing to trust.

```bash
go run . 1730-emission.jws
go run . https://.../2026/08/29/1730-emission.jws
go run . 1730-emission.jws <public-key-hex>
```

Without the key it checks everything except the signature and says so. The public key for a `kid`
comes from [`../../keys/history.json`](../../keys/history.json).

## What it answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed — no key, no network |

**The third one is not a failure and must not be reported as one.** "I cannot check" and "this is
false" are different answers, and a verifier that merges them is worse than none.

## What it checks

1. The **Ed25519 signature**, over the raw text of `header.payload`
2. That `SHA-256(seed)` matches `seed_sha256`
3. That the drand round really carries that `randomness` — asked to drand, not to us
4. That **all 34 variants** reproduce from the seed and the round

## What it does not check, on purpose

It does not verify drand's **BLS signature**. That needs a pairing library, which would mean a
dependency in every language and a build that half the readers cannot run. Instead it asks drand
for the round: the proof that the number is theirs comes from them.

If you want the BLS check too, add it with your language's library — the round travels whole inside
the file, `signature` and `previous_signature` included, so nothing is missing.

## Reuse it

That is what it is for. It is ~300 lines and the interesting part is `derive`, `deriveBlock` and
`stream` — copy those into your project and you have the numbers. The rest is plumbing.

Read [`../../spec/README.md`](../../spec/README.md) first: the three details that break every
reimplementation are listed there, and you will hit all three.
