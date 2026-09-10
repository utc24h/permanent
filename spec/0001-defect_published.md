# Publication notice 0001

| | |
|---|---|
| **Published** | 2026-09-10 |
| **Code** | `defect_published` |
| **Affected turn** | 2026-09-06, 22:10 UTC |

## What happened

The emission for the **22:10 turn on 6 September 2026** was published on GitHub and **never reached
GitLab**. It stayed that way for three days, until it was found by hand on 9 September.

That turn's commitment did reach both anchors, on time: it was signed **1 minute and 51 seconds before**
the drand round that determines the result existed — `committed_at_utc` in the published file reads
`22:08:09`, and the round is born at `22:10:00`. That part — the one that makes it
impossible to have chosen the number — was never in doubt.

**What failed was the copy.** And the effect is concrete: anyone looking only at GitLab saw a
commitment with no emission, with no way to tell a network problem from something being hidden.

## Why it happened

The immediate cause was the network, and it is in the emitter's log:

```
gitlab error 10.002s — dial tcp [2606:4700:90:0:f22e:fbec:5bed:a9b9]:443:
                       connect: network is unreachable
```

DNS returned only the IPv6 address for `gitlab.com` — the IPv4 answer was lost — and the machine
that emits has no IPv6 route. The write died instantly.

That lasts seconds and recovers on its own. **What did not recover was the system**, and that is
where the real defects are:

1. **It did not retry against the anchor that had failed.** With one anchor accepting, the emitter
   considered the turn done and never tried the other again. A second attempt thirty seconds later
   would have fixed everything.

2. **It did not warn.** The alert only fired when **every** anchor failed. With one working, the
   turn ended in silence.

3. **Nothing compared the anchors against each other.** No process asked whether what was published
   in one was also in the other.

4. **The portal was built from a single anchor** — the first one to answer. That day GitHub
   answered, and GitHub had the file, so the portal happened to be right. Had GitHub been down, it
   would have shown a gap over an emission that existed and verified.

Three days of silence were not bad luck: **nothing was watching.**

## What was found while investigating it

Writing the fix surfaced defects in text already published in this repository:

- **The specification said turns are every five minutes.** They have been every ten since 27 August
  2026, and the worked example in `spec/README.md` was built on `05:05`, an instant that is not a
  turn and has no file.

- **The rules for notices contradicted themselves.** `spec/notices.md` said publication notices live
  at `spec/NNNN-*.md` — Markdown — and two lines later that they are *signed with the same key as
  everything else*. A Markdown file carries no signature inside it; both could not be true.

- **The incident report published four fields the specification did not declare**: `variant`,
  `attempts`, `unanchored_commitment` and `warning_en`.

## What was done

**In the emitter:**

- It retries against **the anchor that failed**, and only that one, for the turn's window.
- When a turn ends it compares **the whole day** against every anchor. If something is in one and
  not in another, a signed incident report is published under `<year>/incidents/`.
- It warns when an emission reaches some anchors but not all, not only when all of them fail.
- The startup check now shows **which address** each anchor was reached at, so a problem like that
  day's is visible on the first screen instead of buried inside an error message.

**In the portal:**

- It reads from **every** anchor and shows the union: an emission published in any of them appears.
- There is a reports page listing every incident report, with its explanation.

**In this specification:** the three defects above were corrected. Notices are now declared as
Markdown **and unsigned**, with the reason written next to the rule: a notice informs, it does not
prove. If a signing key were in someone else's hands, signing *"my key was stolen"* with it would
prove nothing.

## What did NOT change

**Nothing that was ever emitted.** No `.jws` file, no signature, no derivation rule and no `version`
field was touched. Everything published so far reproduces exactly as before, and the files for the
22:10 turn on 6 September are byte for byte the ones signed that day.

**And the emission missing from GitLab was not backfilled.** One anchor is enough to prove it, and
putting it there three days late would use the emissions channel to say something that channel
cannot say — that it arrived late. The fact is explained here; the file is not manufactured
afterwards.

## What a third party should check

- The **2026-09-06 22:10** turn is complete and verifies on GitHub: the revealed seed hashes to the
  commitment, drand round 6443386 carries that same value, and the commitment was anchored first.
- On GitLab, `emissions/2026/09/06/2210-emission.jws` **is missing**, and its commitment is there.
- This repository's history shows `spec/README` and `spec/notices` were **modified and never
  replaced**: the previous versions are still in the log, with the date each provider gave the
  commit.
- From this notice onward, a mismatch between anchors appears as an incident report under
  `<year>/incidents/` within the following turn.
