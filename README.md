# permanent

Everything that does not depend on the year: specification, key registry, verifier and manifest.

This is the **permanent** repository: everything that does not depend on the year. The data — the
emissions — lives in a separate repository per year.

> 🇪🇸 En espanol: [`README.es.md`](README.es.md)

## Why they are separate

In the yearly repository **nobody ever edits**. That is an invariant, and anyone can check it with
one command:

```bash
git log --diff-filter=M --oneline    # must return nothing
```

If the specification or the key registry lived in there too, that invariant would be lost: both are
edited by design. On top of that, the emitter's token only needs scope over the yearly repository.

## What is here

| | |
|---|---|
| `spec/` | The specification: with this and a `.jws`, anyone reproduces the numbers |
| `keys/` | The key registry — `kid` → public key + epoch |
| `verifier/` | The reference verifier |
| `manifest.json` | Where everything lives: the yearly repositories and their access routes |

---

Created by `provision/`, not by hand.
