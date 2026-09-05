# `keys/` — the key history

`history.json` maps `kid` → public key. It is **the root of trust for every signature** in the
system.

> 🇪🇸 En espanol: [`README.es.md`](README.es.md)

## The format

```json
{
  "AAAA-MM-DD_HHMM": "<64 hex characters>"
}
```

That is the whole file. Two rules make it readable:

- **The `kid` IS the date the key was generated**, `YYYY-MM-DD_HHMM` in UTC — the same shape as the
  anchor path with the slashes swapped. So opening any `.jws` tells you which epoch its key belongs
  to without opening anything else.
- **An epoch runs until the next key starts.** The last one has no end: it is the active one. There
  is no `status` field because there is nothing to state — the order says it.

A signature dated outside its key's epoch is rejected even if the signature itself is valid. That is
what stops a stolen current key from being used to manufacture a past.

**An empty value means the public key was lost.** It is kept and stated rather than deleted, because
"this cannot be verified" and "this does not verify" are very different claims. A public key cannot
be recovered from an Ed25519 signature: dropping the entry would silently turn a loss of ours into
an accusation against the file.

## Verifying a signature with standard tooling

Next to `history.json` there is **one JWK file per key**, named after its `kid`:

```
keys/AAAA-MM-DD_HHMM.jwk.json
```

```json
{
  "kty": "OKP",
  "crv": "Ed25519",
  "alg": "EdDSA",
  "use": "sig",
  "kid": "AAAA-MM-DD_HHMM",
  "x": "4RvrMJdRNWKR7ylMx8JG2s5dnDJbAyqDfek0fl-K2OM"
}
```

The emitted files are JWS, so any JOSE library — or jwt.io — takes this straight. Read the `kid`
from the JWS header, fetch that file, verify. No conversion needed.

**Both files say the same thing**, one in hex and one in base64url. They are generated from the same
source in the same commit and a test fails the build if they ever disagree. If you find them
disagreeing anyway, `history.json` is the one that counts and we want to hear about it.

A key with an empty value in `history.json` has no JWK file: there is no key left to publish.

## How to read it, which is the part that matters

A signature is verified against the version of the history **contemporary to that signature**, not
against the latest one. The reason: `history.json` is a **mutable** file — it overwrites itself — so
inserting a false key **does not require a `force-push`**, an ordinary commit is enough.

What provides the guarantee is that history cannot be erased:

```bash
git log --follow -p -- keys/history.json
```

> ⚠️ **Honest scope:** this protects against repudiation; it does not prove honesty. And only
> someone who can read a git history can exercise it. Having the tool do it for you is the only real
> answer, and it is not written yet.
