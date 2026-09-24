# Publication note 0003

| | |
|---|---|
| **Published** | 2026-09-24 |
| **Code** | `defect_published` |
| **Turns affected** | 2026-09-24, from 11:10 to 15:30 UTC |

## What happened

On **24 September 2026** GitLab had an incident it declared as a `Partial Service Disruption` on
`Website` and `Git Operations`. An automatic alert opened it at **13:27 UTC**, it was declared
publicly at 13:48, and it was closed as `All Systems Operational` before **21:12 UTC**: about **seven
and a half hours** of declared disruption. The severity went down from 2 to 3 along the way.

The cause it published is **open file descriptor exhaustion** in the service that provides access to
repositories — that is what their own incident record states, in those words.

This system kept emitting. **Every turn of the day was published, none was lost**, and each one has
its commitment and its emission anchored, signed and verifiable. GitHub accepted every write.


**The defect is not in what was emitted: it is in what this system said about what happened.**

Seven incident reports, signed and published, declare that a file was missing from GitLab when the
file **was anchored on GitLab**:

| Report | Declared missing | Reality |
|---|---|---|
| `incidents/2026/09/24/1110-01.jws` | `1110-commitment.jws` | it is on GitLab |
| `1300-01.jws` | `1300-commitment.jws`, `1300-emission.jws` | both are |
| `1450-01.jws` | `1450-commitment.jws` | it is |
| `1500-01.jws` | `1500-commitment.jws` | it is |
| `1510-01.jws` | `1510-commitment.jws` | it is |
| `1520-01.jws` | `1520-commitment.jws` | it is |
| `1530-01.jws` | `1530-commitment.jws`, `1530-emission.jws` | both are |

And an eighth, `1440-01.jws`, is half right: `1440-commitment.jws` is genuinely absent from GitLab,
but `1440-emission.jws` is anchored there.

The other nine reports of the day, from the 13:10 to the 14:30 turns, **tell the truth**: those files
really are not on GitLab, because for that hour and twenty minutes the provider accepted no writes at
all.

## Why it happened

When a write goes out and the answer does not come back, the emitter does not know whether it landed.
To find out, it asks about the file with a second request, separate from the write.

The retry was getting an explicit answer from GitLab:

```
400 Bad Request — A file with this name already exists
```

That is the provider stating that the file is there. But the emitter did not take that answer on its
own: it required confirmation from the second request. And during the incident that request was
taking 8 to 10 seconds against a 10-second deadline, so it often did not come back. **With no
confirmation, the anchor was recorded as missing.**

The outcome depended on whether a read made it within its deadline. Two consecutive turns with the
same reality give opposite results: the 15:30 one declared missing exactly what the 15:40 one
confirmed as present, ten minutes later.

**An outcome that comes out of a race against the clock cannot travel inside a signed file as if it
were a fact.**

`1110-01.jws` shows it within itself: it declares `missing: ["gitlab"]` and a few fields below, in its
own attempt log, it carries the `400 A file with this name already exists` that contradicts it.

## What was found while investigating it

**1. Two different things travelled in the same field.** "It was confirmed not to be there" and "it
could not be confirmed" both ended up in `missing`. The rule that forbids this was written in the
emitter — *not knowing does not authorise concluding that it did not arrive*— and it was lost one
layer above, where both cases fell into the same branch.

**2. The confirmation did not respect the turn's clock.** Its only ceiling was its own 10 seconds,
without looking at how much was left. The margin that protects the next turn's start is calculated
for a 15-second attempt, and with the confirmation in between an attempt could last 25. No emission
was lost because of this — the margin floor is 127 seconds against about 70 in the worst measured
case— but the guarantee was written and was not being met, and the commitment ended up anchoring
closer to its round than the design reserves.

**3. Nothing raises a false report.** The portal considers explained any report that carries its
attempt log inside, and the automatic alert does not insist about what is explained. A false report
**with** a log meets both conditions. The seven were found by comparing by hand, file by file,
against both repositories.

**4. And the incident reports ended up uneven too, with nothing declaring it.** Ten of them are
missing from GitLab: `1300-01.jws` and those of the 13:10 to 14:30 turns. They are published through
the same path as everything else, so when the provider was accepting no writes they did not land
either.

The check that compares both anchors looks **only** at the emissions directory. The incidents one is
read for a different purpose — knowing which turns already have a report, so as not to declare the
same thing twice— and there it is enough for the file to be in **one** of the two. Correct for
avoiding duplicates, and blind to the gap.

⚠️ The awkward effect: the report for the 13:10 turn, which is the one declaring that files from that
turn are missing from GitLab, **is itself missing from GitLab**. Anyone looking only at that
repository sees the gap without the explanation beside it. It is on GitHub, signed, and the portal
shows it all the same.

## What was done

**In the emitter:**

- What was confirmed is separated from what could not be confirmed. `missing` carries **only** the
  anchors that answered that the file is not there.
- When nothing could be confirmed, the report's reason is **`anchor_timeout`** — *the write went out
  and we did not see the answer*— which was already in this specification's closed list beforehand.
  The anchors that are not known about are named in `unconfirmed`: they are named, not asserted.
- The confirmation **cannot overrun the turn's deadline**. It uses its own timeout when there is time
  to spare, and whatever is left when there is not.
- **Retrying continues against everything that is missing**, including what could not be confirmed.
  Stopping insistence on a gap that may be real would be worse than declaring it wrong.

**In the portal:** a new case. There used to be two — "missing in X" and "it reached every anchor"—
and a report with no `missing` fell into the second by elimination, which would have published *"it
reached every anchor"* about precisely what is unknown. It now says **"it could not be confirmed on
X"**, and next to it how to check that with no credentials.

**In this specification's list of reasons:** nothing. No code was added or changed. `anchor_timeout`
was already published, with exactly the meaning that was needed.

**And in this document, one sentence that contradicted another of its own.** It said *"Three signed
instruments"* when introducing them, and thirty-seven lines further down it explained that a note
goes *"in Markdown and unsigned, on purpose: the note informs, it does not prove"*. Of the three,
**only the incident report is signed**; the two notes are not, and that is deliberate and reasoned
right there — signing "my key was stolen" with the stolen key would prove nothing.

What the three share is not the signature: it is that they **sit in a repository that is not
rewritten, with the date the provider stamps**. The adjective was spare, so it was removed. It is
declared here under the same criterion note `0002` used for the year that would age: a wording fix
gets named, it does not slip in unannounced.

## What did not change

**Nothing that was emitted.** No `.jws` file, no signature, no derivation rule, no number. All 96
Everything emitted that day reproduces the same as before this note.

**The eight reports with the incorrect declaration stay as they are.** A published file is not
rewritten. Each one carries beside it, in the portal, a text stating which file is anchored and in
which commit, with the date the provider stamped.

**The 18 files that really are missing from GitLab are not replaced.** They are the 13:10 to 13:50
and 14:10 to 14:30 turns in full, plus `1400-commitment.jws` and `1440-commitment.jws`. **Nor are the
10 absent incident reports**, for the same reason. Uploading them later would
carry a date after their round, and would use the emissions channel to say something that channel
cannot say. Those turns lost redundancy, not proof: they are anchored on GitHub, signed, and they
verify.

## What a third party should check

- The files the seven reports declare missing **are on GitLab**, each with its commit and with the
  date GitLab stamped. It reads with no credentials:

  ```
  commits?path=emissions/2026/09/24/1510-commitment.jws
  ```

  That one, for instance, is in commit `cc90a4998de9a74c55b92c0e1f0c6a847a7c2a0c`, stamped by GitLab
  at **15:08:33 UTC** — **six seconds before** the emitter gave the write up for lost. The same
  contrast repeats across all seven: between 6 and 21 seconds.

- The files from the 13:10 to 14:30 turns **really are not on GitLab**, and their reports declare that
  correctly. The difference between the two groups is checkable file by file.

- Every turn of the day has its commitment anchored **before** the drand round that determines its
  result existed, and that date is stamped by the provider.

- The reports carry their attempt log inside, signed, with the time and the answer of each one. In
  seven of them that log **contradicts** what the same file declares, which is exactly the defect this
  note records.

- The provider's incident is public and checkable, with its own timeline and its own timestamps.

- From this note onwards, an anchor that could not be confirmed at all is declared `anchor_timeout`
  and appears in `unconfirmed`. **If a report says `missing`, it is because someone answered that the
  file is not there.**
