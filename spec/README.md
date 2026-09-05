# `spec/` — the published specification

What is needed for **anyone** to reproduce the numbers without our code:

1. The inputs: `seed`, `round.randomness`, `drand_round`
2. The derivation context: `version|variant|round`, plus `|bN` per block
3. The stream: `info = context‖"|"‖bytes_already_generated`, 64-byte blocks via HKDF-SHA256
4. The unbiased integer: `cut = (space/range)*range`, discard and retry
5. The 6 shapes, with their exact rule
6. The version convention: `0.x` is a test, an integer is history

> 🇪🇸 En espanol: [`README.es.md`](README.es.md) · Signed notices: [`notices.md`](notices.md)

## Why this is published and not the emitter

A verifier was written in Python from scratch, using only the file and the document, and it
reproduced **8,262 of 8,262** results. If a third party reaches the same numbers with that, there is
nothing else to hand over.

---

## The six global rules

Ambiguity here is what makes an honest emission look like a lie. **R2, R5 and R6 are the three that
make a badly written verifier accuse a legitimate file.**

| | Rule |
|---|---|
| **R1** | Hex is lowercase, with no prefix |
| **R2** | Hashes are computed over the **decoded bytes**, never over the hex text |
| **R3** | Times are UTC, RFC 3339, with `Z` |
| **R4** | A SHA-256 is always 64 hex characters |
| **R5** | The signature is verified over the **raw text**. Re-serializing the JSON changes the bytes and breaks a signature that is perfectly valid |
| **R6** | The file travels as binary and is not touched. No re-encoding, no trailing newline, no editor |

## Which drand round belongs to a turn

**There is a turn every 10 minutes, on the clock, always UTC:** `HH:00`, `HH:10`, `HH:20`, `HH:30`,
`HH:40`, `HH:50`. 144 turns a day. Any other instant is not a turn and has no file.

**The target round is not chosen. It is derived**, and this is what makes it impossible for us to
name a round that suits us:

> The target round of a turn is **the one whose nominal time is exactly the turn's time**.
>
> ```
> round = (turn − genesis_time) / period + 1
> ```
>
> `genesis_time` and `period` come from the drand chain, which is pinned inside every file as
> `drand_chain_hash` and `drand_public_key`.

Anyone can recompute it and check that the file names the round it had to name. A file whose
`drand_round` is not that one is invalid, no matter how well everything else verifies.

This also fixes when the number comes into existence: the round is born **at the turn**, so the
result cannot exist before its own turn.

## The cut-off is the turn

The result is published a few seconds **after** the turn — that is the time it takes to read the
round, derive and push. Never before: publishing early would mean deriving from an earlier round,
and then the number would exist before its turn.

Which leads to the rule anyone building on this must follow:

> **Nothing that depends on an emission may accept entries after its turn.**

Anyone who publishes anything knows it before the reader does, for as long as publishing takes.
Closing at the turn makes that interval worth nothing.

---

## Missing turns, and how to check that each one is explained

A turn can be missing from the history. That is expected, and **every gap must carry its
explanation in the turn right before it.** This is what makes the rule checkable instead of
something you have to take our word for.

**The rule:** while a turn is not closed, no new turn starts. A commitment that was published
must end in an `-emission` or a `-failure`; until one of those exists, the emitter does not begin
another turn.

**So a gap is read backwards:**

```
emissions/2026/08/22/0510                missing
emissions/2026/08/22/0500-emission.jws   with  "recovery": { "code": "emitted_after_expiry", ... }
```

The 05:00 turn was closed late. While it was open, 05:10 could not start. That is the whole
explanation, and it is in a signed file.

**What counts as explained.** A gap is explained when the previous turn's `-emission` carries a
`recovery` note, or when that turn ended in a `-failure`. Both are signed and both say why.

> 🔎 **And the reverse is the guarantee: a gap with a clean turn before it — an `-emission` with no
> `recovery` note — is an anomaly with no explanation, and you should treat it as one.** Anyone can
> walk the history and check that every gap has its reason next to it. We cannot hide a skipped turn
> behind a normal-looking one.

**Why a late emission is published at all.** The result is a deterministic function of a seed
committed beforehand and a drand round named beforehand. Publishing it late gives us no freedom
whatsoever — the number was already fixed. Voiding the turn instead *would* have given us freedom:
an operator who can cancel a turn by stalling can cancel the ones it dislikes. So the number always
goes out, and the delay is declared.

---

## The three details that break a reimplementation

These are not edge cases. Every reimplementation so far has hit all three.

**1. For simple variants, the mold is the group name, not a field.**

Only `composite` carries an explicit `blocks` array. Everything else carries its parameters flat,
and the mold is the key of the group it sits in:

```json
"discrete_uniform": { "u-0-9": { "min": 0, "max": 9, "result": 2 } }
"composite":        { "s-5-of-50-and-2-of-12": { "blocks": [ … ], "result": [[…],[…]] } }
```

**2. `random_matrix` carries `rows` and `cols`, not `count`.** The number of values to draw is
`rows × cols`, and the result is published as a list of rows.

**3. `truncated_continuous` publishes `min` and `max` already multiplied by `scale`.** Do not
multiply again. With `min: 1000, max: 1000000, scale: 1000`, the span is read straight off the
file:

```
value = min + integer(max − min + 1)
```

## The shape of `result` depends on the mold

| Mold | `result` |
|---|---|
| `discrete_uniform` | a scalar — `2` |
| `sample_without_replacement` | a sorted list — `[3, 11, 24]` |
| `uniform_vector_with_replacement` | a list, order matters — `[1, 0, 1]` |
| `permutation` | a list, the order **is** the result — `[8, 5, 4, …]` |
| `truncated_continuous` | a scalar, read it with `scale` — `833590` |
| `random_matrix` | a list of rows — `[[1,4,7],[2,9,0]]` |
| `composite` | one list per block — `[[7,12,30],[2]]` |
