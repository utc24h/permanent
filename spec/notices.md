# `spec/notices.md` — what we publish when something changes or breaks

## Why this document exists

**This system is a constitution that regulates itself.**

Nobody can know today what will need changing in 2031. What can be done is to write down, in
advance and in public, **how it changes without breaking trust** — and to be bound by that.

It is the same reason the **RFCs** exist: a protocol meant to last decades does not rest on the good
will of whoever maintains it, but on a public procedure anyone can check was followed. The rule does
not protect whoever writes it: it binds them.

That is where the property that makes everything else verifiable comes from: **if a change required
a notice and the notice is not there, the change is illegitimate** — and a third party settles that
by looking at dates, without asking us anything.

---

Three signed instruments, and they are not interchangeable. Each answers a different question, and
knowing which one to expect is what lets you catch us skipping it.

> 🇪🇸 En espanol: [`notices.es.md`](notices.es.md)

| Instrument | Answers | When |
|---|---|---|
| **Change note** | "this is going to change" | **before** a planned change |
| **Publication note** | "this happened and you need to know now" | when it happens |
| **Incident report** | "this turn did not go as it should" | attached to the turn |

---

## 1. Change note

Published **before** the change, never after. If a change that needed one appears without it, the
change is illegitimate — that is the point of the rule.

A change note is required for anything that alters what a verifier must do:

- Raising the `version` field. This one is not cosmetic: `version` is part of the derivation
  context, so raising it **changes every number**. The note goes out first, and only then the code.
- Adding or removing a variant from the catalogue.
- Changing the randomness source.
- Changing the file format, the rules, or the six global conventions.

It carries: what changes, why, the date it takes effect, and the first turn that will run under the
new rules. Anything published before that turn keeps reproducing under the old rules — which is
exactly why the version travels inside each file.

## 2. Publication note

For what is not planned: a compromised key, a provider lost, a defect found in something already
published. It is the only one of the three written under pressure, so its form is deliberately
small.

It carries: the UTC instant, a `code` from the closed list below, what happened, what was done, and
what a third party should check. Signed with the same key as everything else.

```
key_compromised       a signing key is, or may be, in someone else's hands
anchor_lost           a repository is gone, or stopped accepting writes
defect_published      a defect was found in something already published
service_interrupted   emission stopped, and it was not a single turn
```

The list is closed for the same reason the incident codes are: so the sentence can be rendered in
any language, and so we cannot soften a bad week with a wording nobody compares.

**It never rewrites anything.** A published file is not corrected, deleted or replaced — the note
says what is wrong with it and stays next to it. A history that can be corrected is a history you
have to trust.

## 3. Incident report

Attached to a turn that did not go as it should. It is signed, it goes to `incidents/` in the year
repository, and — this is the part that matters — **it can exist without an emission**: it is the
only way to explain a turn where nothing at all was published.

Its shape:

| Field | |
|---|---|
| `type` | `"incident"` |
| `status` | `"unresolved"` or `"resolved"` |
| `emission` | the turn it belongs to |
| `part` | `1`, `2`, `3`… the sequence, when one turn needs several |
| `reason` | **an identifier, never prose** |
| `reason_data` | the numbers behind the reason |
| `opened_at_utc` | when it was opened |

`reason` comes from a closed list so that anyone can render the sentence in any language, and so
that we cannot bury a bad turn under a wording nobody compares:

```
anchor_timeout        the write went out and we did not see the answer
anchor_unreachable    no repository accepted the write
anchor_too_late       the commitment landed after its round already existed
beacon_unreachable    the drand round could not be read within the window
beacon_invalid        a relay answered something that does not verify
unknown_state         we could not determine what happened
```

## Keys: what may be done to the registry

The key registry (`keys/history.json`) is the root of everything: it says which public key each
`kid` refers to, and without it no signature can be checked. That is why changes to it are the most
tightly governed in the whole system.

**There is only one legitimate operation: adding an epoch.**

| Operation | Allowed? | With which instrument |
|---|---|---|
| Add a new key | **yes** | change note, published **beforehand** |
| Add a new key urgently | **yes** | publication note, `code: key_compromised` |
| Change the value of an existing entry | **never** | - |
| Remove an entry | **never** | - |

Removing an entry frees nothing: **it kills everything that key signed.** Without its public key,
that stretch of the record can never be verified again. That is why a rotation limits the damage
**going forward and not backward**, and why old keys stay even once they are no longer used.

Each epoch also leaves its own file, named after the `kid` - and the `kid` is a date, so the history
sorts itself. Earlier files are never touched. The format and how to read it are in
[`keys/README.md`](../keys/README.md).

### How a key is changed, and what each thing proves

There is no revocation: nobody can "switch off" a published key. What happens is that we **declare
from when we stopped using it** and start emitting with the new one. The old one stays in the
registry forever, because it remains the only way to check what it signed.

A lost or leaked private key **changes nothing about the past** -what was published is already
anchored, dated by third parties and held in repositories that are not only ours- but it **can be a
nuisance in the present**, because whoever holds it can manufacture files that verify.

The three cases are not defended the same way, and they should not be conflated:

| Case | Is the handover signed with the old key? | What provides the guarantee |
|---|---|---|
| **Planned rotation** | **yes**, and with the new one too | the signature with the old key: the same owner hands over |
| **Lost key** | impossible: it no longer exists | the anchor - the new entry arrives dated by a third party |
| **Stolen key** | possible, **but proves nothing**: the thief can sign too | who published first, and through the usual channel |

> **So when a key leaks, publishing fast is not tidiness: it is the whole defence.**
> We do not win because our signature is different -it is not- but because the notice arrives
> **first**, anchored, in the same repositories we have been publishing to since the first turn.
> Whoever shows up afterwards has to explain why their version is nowhere.

### The procedure, in order

1. **Stop emitting.** Stopping is part of the procedure, not a failure: carrying on with a doubtful
   key litters the record with files that then have to be argued over one by one.
2. **Add the new key** to the registry, as one more epoch.
3. **Publish the notice**, stating the exact stretch -from which turn to which turn- in which the
   old key may have been compromised. Signed with the new key, and with the old one too if it is
   still held and the case warrants it.
4. **Resume**, emitting with the new key.

The declared stretch is what matters: **outside it, everything signed with the old key still
stands.** A leak does not invalidate four years of record, it invalidates a window - and stating
which window, precisely and in writing, is exactly what these instruments exist for.

### Where the answer is published, and why not on the portal

The notice goes **to the anchor repositories**, not to the site. The portal shows it because that
is convenient, but that is not where the proof lives.

The reason orders the whole design: **a domain gets lost.** A complaint to the registrar suspends
it without a trial and within days, a provider closes an account, a server goes dark. If recovery
depended on the site, knocking the site down would be enough to stop us answering.

Instead the notice lands where everything else already is:

- on **two independent providers**, which are not ours;
- in a history **continuous since the first turn**, which cannot be rewritten without a trace;
- with **a date set by them**, not by us.

So if one day this portal does not answer, **the system has not gone down**: a convenience has. The
files, the key registry, the specification and the notices are all still where they always were,
and they can be read without us.

> **And that is the only way to spot an impostor.** If another site shows up claiming to be this
> one, with a notice signed by an old key, do not believe them or us: look at **where their history
> is**. Ours runs unbroken from the first turn, anchored and dated by third parties. Theirs starts
> the day it appeared.

### How you check it, without taking our word

```bash
git log --follow -p -- keys/history.json
```

It must show **added lines only**. Not one modified, not one removed. If anything else shows up,
there is your proof and it needs no argument with us.

> **Honest scope, worth stating here too:** this protects against repudiation -we cannot later deny
> what we published earlier- but it **does not prove honesty**. And today only someone able to read
> a git history can exercise it.

---

## Where each thing lives

**The rule: rules where they are revised, facts where they happened.**

| What | Where |
|---|---|
| These rules | `permanent` -> `spec/notices.md` |
| Every change note and publication note | `permanent` -> `spec/NNNN-*.md` |
| Every incident report | that year's repository -> `<year>/incidents/` |

This is not a matter of tidiness, and the two families **do not promise the same thing**:

| | What it guarantees | How you check it |
|---|---|---|
| `<year>/` | **Nothing ever changes.** No file is modified or removed | a single command over the history |
| `permanent/` | **Nothing is removed or altered. Only added** | each file's history shows added lines only |

Incident reports go to the year because they are **facts**, and they belong to the year they
happened in.

### The permanent repository DOES change, and it has to be able to

Saying "nobody ever edits here" would be false. If a signing key is lost or ends up in someone
else's hands **it has to be replaced**, and that touches `keys/history.json`. What never happens is
rewriting.

When a key is compromised:

1. A new epoch is **added** to the registry, with the new key.
2. The old entry **stays forever**. Deleting it would kill everything that key signed: without its
   public key, that stretch of the record can no longer be verified and dies with it.
3. A **publication notice** goes out with `code: key_compromised`, stating from when the old key
   cannot be trusted.

That is why a change of meaning goes into a **new** document and never on top of the old one. A
rotation limits the damage **going forward, not backward** - and what protects the past is not
having destroyed anything, but that these repositories are append-only, carry a third party's date
and are not only ours.

> **The check, and it is mechanical:** the history of `keys/history.json` must show **added lines
> only**. Not one modified, not one removed. If you ever see otherwise, you do not need to argue
> with us: there is your proof.

---

## This document changes too, and by its own rules

Nothing above is final. Things will come up that cannot be foreseen today, and some of these rules
will turn out to be wrong. **That is expected: changing them is legitimate.**

What is not legitimate is changing them **quietly**.

> **This document is governed by rule 1 of this document.** Modifying it requires a **change note,
> published beforehand**, exactly like changing a file format or the variant catalogue. If you ever
> find that these rules changed and there is no note announcing it, **that change is illegitimate**
> - by the very rule you are reading.

That is what makes it a constitution rather than a rulebook: **it applies to itself.** A text that
says how everything changes, but which can be changed without notice, binds nobody - least of all
whoever wrote it.

So the guarantee does not depend on us staying the same people, or on us continuing to think the
same way:

```bash
git log --follow -p -- spec/notices.md
```

This file's history is public, append-only and dated by third parties, like everything else. Every
version that ever existed is still there, and can be read next to the note that announced it.

**If the two do not match, the one that counts is the anchored one - and we have some explaining to
do.**

---

## What this buys you

Every gap in the history has a signed file next to it, and its reason comes from a fixed list. So
the check is mechanical, not a matter of reading our prose:

> **A gap with nothing next to it is an anomaly. Treat it as one.**

We cannot hide a skipped turn behind a normal-looking one, and we cannot explain one away with
wording invented after the fact.
