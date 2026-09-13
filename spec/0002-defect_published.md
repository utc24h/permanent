# Publication notice 0002

| | |
|---|---|
| **Published** | 2026-09-13 |
| **Code** | `defect_published` |
| **Turns affected** | 2026-09-13, from 08:50 to 10:00 UTC |

## What happened

On **13 September 2026**, between 08:47 and 09:58 UTC, GitHub rejected sixteen writes from this
system with `HTTP 500` and `HTTP 502`. GitLab accepted every one of them, on the first attempt, from
the same machine and in the same second.

Five turns were affected. In four the file went through after retrying. **In the 09:00 turn it did not**:
`emissions/2026/09/13/0900-commitment.jws` is in GitLab and missing in GitHub.

That turn verifies as usual. GitLab accepted the commitment on the first attempt and stamped its
commit at **08:57:55 UTC**, **125 seconds before** drand round 6461966 existed — the round that
determines the result. What that turn lost is redundancy, not proof: the commitment sits in one
provider instead of two.

## Why it happened

The immediate cause is the provider's, and the provider declared it. GitHub opened a critical
incident that same day, from **09:16 to 10:44 UTC**, with this explanation:

> *«increased database replication delays on collab which is causing increased error rates in
> authorization endpoints and follow-on increased error rates across the system»*

and mitigated it by shedding load at the edge. Our first rejections are from 08:47 — **29 minutes
before the incident was declared**.

The emitter did what it had to do: it retried GitHub five times between 08:57:58 and 08:59:22, and
stopped because there was no time left. **The commitment has to be anchored before its round is
born**, and a sixth attempt fell past the cutoff. That is not a defect: that is the rule working.

## What was found while investigating it

The defects are in what the system **said** about what happened, not in what it emitted.

1. **Five signed incident reports declare `unknown_state`, and that is false.** This repository
   publishes that code meaning *«it could not be determined what happened»*. In all five it was
   determined perfectly well:

   - In the 08:50, 09:10, 09:30 and 10:00 turns the file **did** go through, after retrying, and
     the report itself carries the log with the time and HTTP code of every attempt. A signed file
     that contradicts itself.
   - In the 09:00 turn the file **did not** go through, and which file and which anchor were known:
     the report says so in its own `files` and `missing` fields.

2. **The closed list of reasons had nowhere to put either case.** `anchor_unreachable` means *«no
   repository accepted the write»*, and in both cases one did accept. There was no code for «it
   reached one anchor and not the other», nor for «it reached every anchor, but retrying was
   needed», so both fell into `unknown_state` by elimination.

   That list is the vocabulary of a **turn failure** — why this turn produced no result — and the
   incident report was using it to answer a different question: what happened operationally.

3. **The 09:00 report was published without the attempt log**, even though `attempts` is declared in
   this specification and the other four do carry it. The reason: that report was written by the
   sweep, which compares file listings and knows *what* is missing but not *why*. The five
   rejections were in the same process's memory, 105 seconds earlier, and did not travel.

   **The turn that needed the log most was the only one published without it.**

4. **This document talked about the year 2031.** It said *«nobody can know today what will need
   changing in 2031»*. The year was an example and it ages by itself: read in 2031 it says the
   opposite of what it means.

## What was done

**In this specification's list of reasons**, two new codes:

```
anchor_partial        it reached one anchor and not the other
anchor_retried        it reached every anchor, but retrying was needed
```

With those, `unknown_state` goes back to meaning what it says: it is left for what genuinely is not
known — a turn from another day, or one orphaned because the emitter went down before declaring it.

**In the emitter:**

- The report is declared by **the turn**, which is what holds the data, and not by the sweep. In
  both cases, with the code that fits and **with the attempt log inside**.
- The sweep stays as the safety net, for what the turn did not manage to declare. There, and only
  there, `unknown_state` is literal.
- The margin between the anchoring and the round is measured from **the date the provider stamps**,
  which is the only one of the anchoring a third party can check. It used to be measured from our
  own clock after the retry loop ended, which in this very turn reported 37 seconds where there
  were 125.

**In the portal:**

- The reports page tells the story on its own for reports whose code carries the numbers, with the
  attempt log as a table. The others still wait for a person to write them.
- Every time is shown in the reader's own time zone.

**And in `spec/README`, a change that travels in the same proposal and is not part of this:** a
sentence was added at the top saying, in the words the standard uses, what this specification
defines — results that are *verifiably random and auditable*. It had been written since 11
September and never published. It is declared here so that it does not slip in unnamed.

## What did NOT change

**Nothing that was emitted.** No `.jws` file was touched, no signature, no derivation rule, and not
the `version` field. Everything published reproduces exactly as before.

**And the five reports that say `unknown_state` stay as they are.** A published file is not
corrected, not deleted and not replaced: this notice says what is wrong with them and stays next to
them. That they say less than was known is a defect; rewriting them would be a worse one.

**The commitment missing in GitHub was not replaced.** Uploading it later would carry a date after
its round and would read as a commitment that arrived late. The fact is explained; the file is not
manufactured after the event.

## What a third party should check

- `emissions/2026/09/13/0900-commitment.jws` **is in GitLab and missing in GitHub**. Its emission,
  `0900-emission.jws`, is in both.
- The date GitLab stamped on that commit is **2026-09-13T08:57:55Z**, earlier than the nominal time
  of round 6461966 (09:00:00Z). It reads without credentials:

  ```
  commits?path=emissions/2026/09/13/0900-commitment.jws
  ```

- The reports for the 08:50, 09:10, 09:30 and 10:00 turns carry, signed, **eleven** attempts with
  their time and response code. The five from the 09:00 turn travel in no file at all: they exist
  only in the emitter log, which is precisely the defect this notice declares. They match the incident GitHub declared that day between 09:16 and 10:44 UTC.
- This repository's history shows that `spec/notices.md` was **modified and never replaced**: the
  earlier versions remain in the record, with the date the provider stamped on each commit.
- From this notice onward, a turn where a file reaches some anchors and not all is declared with
  `anchor_partial` **within the turn itself**, and with the attempt log inside.
