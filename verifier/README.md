# `verifier/` — reference verifiers

One folder per language. Each takes a `.jws` and checks, step by step and in the open:

- the Ed25519 signature against the key for its `kid`, resolved in [`../keys/`](../keys/)
- the commitment: that the revealed seed hashes to the value committed beforehand
- the drand round against the original source
- that the result **reproduces** from the seed and the round

> 🇪🇸 En espanol: [`README.es.md`](README.es.md)

| | Needs |
|---|---|
| [`go/`](go/) | nothing. Standard library |
| [`js/`](js/) | nothing. WebCrypto, Node 18+ or a browser |
| [`py/`](py/) | `cryptography` for the signature only |
| [`cpp/`](cpp/) | OpenSSL and nlohmann/json |
| [`delphi/`](delphi/) | `libcrypto` for the signature only |

**All five verify the same file and reach the same result.** That is the point: if five independent
implementations agree, the specification is enough — and if yours disagrees, the specification says
where to look.

## About dependencies

The rule is not "zero dependencies". It is **nothing that can disappear or rot**.

OpenSSL is the most audited cryptographic library there is, it will outlive everyone reading this,
and it is faster than anything hand-rolled. Where a language does not carry Ed25519 in its standard
library, using it is the right answer — not a compromise. What is avoided is the small package with
one maintainer that vanishes in three years and takes your build with it.

Every folder states its dependency, where it comes from, and what happens without it.

## The three answers

| | |
|---|---|
| `VERIFIED` | signature, commitment and every number reproduce |
| `NOT VERIFIED` | something does not match. The file is not what it claims |
| `UNVERIFIABLE` | the check could not be completed — no key, no network, no library |

**The third is not a failure and must not be reported as one.** "I cannot check" and "this is
false" are different answers, and merging them is how an honest emission gets called a lie.

## What they do NOT do

They pass no judgement beyond that. They show the computation; the conclusion belongs to whoever
looks.

> ⚠️ On a `version` starting with `0.`, the emission is a **test and not part of the history**. It
> verifies correctly and should be read as information, not as a failure.
