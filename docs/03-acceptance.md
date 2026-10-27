# Acceptance contract

## Distinct claims

Use these words precisely in reports. Each one proves only its own row.

| Claim | Proves |
|---|---|
| Extracted | complete saved-disc inventory + SHA-256 manifest + representative decode |
| Prepared | original's structure, timeline and metadata passed preparation checks |
| Encoded | encoder finished all expected frames, end marker present, zero dup/drop |
| Verified | both complete editions passed every full-film gate below |
| Published | immutable accepted media and the current catalog/aliases are served correctly |
| Delivered | the named device shows the intended entries and preservation checks passed |
| Human spot-check | only the part the human actually watched/listened to |

## UHD full-film gates

- The full original and streaming video **and every intended audio stream** decode cleanly to the end: exact expected video frame count, zero dropped/duplicated frames, empty error log. (`examples/decode_verify.py`)
- Actual starts, ends, cadence and per-track timelines are preserved. Container duration is not a substitute for each stream's real endpoint.
- Copied tracks preserve packet payload, size, count, order, PTS, DTS and duration under an exact comparator (`examples/packet_compare.py`). When an aggregate digest differs, diagnose each field separately; the aggregate doesn't tell you which one broke.
- Where mux/lacing changes are involved, compare decoded PCM and sample timing too. Unknown/absent timestamps are not equivalent to invented numeric ones.
- Chapters: count, titles, start and end. Metadata-only chapter fixes must leave media bytes unchanged.
- HDR: measure static mastering-display and content-light metadata from *this* title and carry it over exactly. DV: profile, RPU presence, RPU frame count, active-area/crop mapping. Streaming conversion needs a proven RPU round trip.
- Source/backup identities unchanged; final outputs hashed; archive readback hashed.

## No silent waivers

- No generic tolerance widening, trimming, padding, trusting a mutable `DURATION` tag, or "looks playable" substitution for a failed gate.
- Exceptions are **per title**, evidence-linked, and recorded as decisions. Example: a known pre-existing decode error in the *source* accepted after strict output checks plus a human spot-check around the affected timestamp. That is not a general source-error tolerance.
- "We'd accept a bounded 1 ms timing-only rounding" is not permission for missing audio, altered payload or accumulating drift. Prefer an exact fix when one exists.
- Investigate only what decides the gate; reuse valid completed encodes.

## Every check needs controls

Before a check gates anything:

- **Omission control:** missing stream, missing field, empty packet list, target never reached → FAIL. Compare key sets in both directions.
- **Mutation control:** one changed payload byte or timestamp → FAIL.
- **Dry run on known-good input:** a new harness runs once on a build you already trust before it gates a new one.
- A probe that reports 0 of something counts only after it has reported >0 on a forced positive case.
