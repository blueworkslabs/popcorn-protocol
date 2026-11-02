# Case study: frames out of order on a MediaTek HEVC decoder

A streaming stick showed short "bounces" in UHD HEVC: the picture jumped a frame ahead and back, in the same scenes but not on every replay. It took a day to separate the real cause from three plausible-looking ones. The workaround lives in its own repository, because it is a Kodi patch (GPL) and this playbook is MIT: [kodi-mtk-hevc-workaround](https://github.com/blueworkslabs/kodi-mtk-hevc-workaround).

**Scope of what was proven:**
- one device family (Fire TV Stick 4K Max, 2nd gen; `OMX.MTK.VIDEO.DECODER.HEVC`; Kodi 21.3; Surface rendering);
- 23.976 fps HDR10 HEVC;
- the human's verdict in the tested scenes.

Nothing here shows the same fault on other devices, frame rates or Dolby Vision, or the exact firmware cause.

## Symptom

Brief back-and-forth jerks, about once every few seconds in busy scenes. They were not buffering: the cache stayed full. They were not every replay either: the same scene bounced on one replay and not on the next.

## Leads that were real but not the cause

Each of these changed something, which made it look like the cause. None removed the bounce.

- **Transport.** SMB, HTTP and NFS changed start-up and buffering behaviour; see [clients](05-clients.md). A local copy on the device still bounced.
- **Audio offset and subtitles.** These changed how often stutter showed in one edition. With zero offset and subtitles off, UHD still bounced.
- **A known Kodi issue** with a patch that sorts adjacent frames whose timestamps go backwards. Built and tested: it never triggered, because this decoder's timestamps never go backwards (see below).
- **Uneven presentation intervals in the logs.** True, but they don't say which frame is shown.

## What found it

1. **Compare what goes into the decoder with what comes out.**
   - Kodi's debug log, with the `video` component on, lists every timestamp queued to MediaCodec and every timestamp it hands back.
   - A few output timestamps had never been queued, and the same number of queued ones never came back.
   - The output always jumped about 125 ms forward, then moved in +16 ms steps, so it stayed increasing.
2. **Look at where it happens.** In the source (closed GOP, an IDR about every second), every anomaly sat on the last frames before an IDR. Only some IDRs were affected. That is consistent with timing inside the decoder; the exact firmware mechanism is unproven.
3. **Prove what the screen shows.** Timestamps cannot tell "right frames, wrong timing" from "wrong frames".
   - The human filmed the TV with a phone at 120 fps, the agent captured Kodi's log in the same run, and each filmed frame was matched against a reference software decode of the source.
   - The matching was perspective-corrected and compared high-pass detail in two separate image regions, without forcing the order to move forward.
   - Two independent events showed the frames as **A D B C E** instead of A B C D E, at the exact log positions of the anomaly.
4. **Don't trust a clean run.** Several software probes (screen recording, decoding to buffers outside Kodi) decoded hundreds of frames in correct order without a single anomaly. They proved only that the fault did not occur in those runs.

## The fault

| What | Before the keyframe |
|---|---|
| The frames, in presentation order | A B C D, then keyframe E (in decode order D was queued before B and C) |
| Handed back | A, D with its own timestamp, then B and C labelled D+16 ms and D+32 ms, then E |
| Shown | A D B C E |

The labels hide the reversal: they keep increasing, so every "timestamps must not go backwards" check passes.

## The workaround, in one paragraph

Kodi keeps a ledger of queued timestamps. When a frame comes out while earlier queued frames are missing, it holds that frame. Frames that then arrive with never-queued labels 12–20 ms apart get the missing timestamps back in order, and the held frame follows them. Everything else falls back to the decoder's order:
- an unrelated label;
- a near-repeat of the held frame's timestamp;
- a frame without a timestamp;
- a drain;
- a hold older than 250 ms, released on the next codec poll (not by an independent timer during a pause).

It is enabled only for that decoder, Surface output and plain HEVC; Dolby Vision is excluded. Details, tests and limits are in the companion repository.

## What independent review caught

The first candidate passed its own 42 tests and was still wrong in three ways. Each later round found more.

- **The gate read a value that setup had already changed.** It compared the decoder's display name to `amc-hevc`, but configuration had appended `(S)` for Surface output, so the workaround never switched on. Gate on properties that don't change after setup (mime type, decoder name, output mode), and check them at the point they are read.
- **End of stream released the held buffer.** Kodi's drain releases every output buffer it owns, including the one held back. Hand it over before the drain starts. Kodi's drain can still drop frames already queued for display; that is existing behaviour, not something the workaround fixes.
- **"Unknown timestamp" is not identity.** Any never-queued label above the held frame was taken as a late frame. So were a label 5 seconds away and one a microsecond off the held frame. Accept only the observed signature, and fall back otherwise.
- **A frame without a timestamp bypassed the held frame**, giving A X D E instead of the decoder's A D X E. Every result now goes through one hand-over function, which the tests drive as well.

## Lessons

- Monotonic timestamps and a full cache do not prove correct frame order. Only the screen does: film it and match frames to a reference decode.
- Get the fault and the identity evidence **from the same run**. Separate runs prove less, because intermittent faults come and go.
- A plausible lead that changes the symptom is not the cause until removing it removes the symptom.
- Write the workaround around the evidence you have: one held frame, narrow bounds, and fall back to unchanged behaviour on anything else.
- Fixtures from real logs make strong regression tests. Strip them to decoder events and shift timestamps before sharing. The expected order should come from the filmed frames, not from the code under test.
- Have someone else review the integration, not just the logic. All of the bugs above were in the code around a correct-looking core, or in what "unknown" was allowed to mean.

## Claim boundaries

- **Seen:** no bouncing in the tested scenes. The log of that run shows the workaround active, with 25 corrected events and no fallbacks.
- **Not shown:**
  - other titles watched start to finish with the workaround;
  - measured A/V sync;
  - seek and stop behaviour on the device;
  - other frame rates, devices or Dolby Vision;
  - the firmware-level cause.
- **Second device:** a second stick of the same model got the same build, with library, start-up and shut-down checks only. There is no playback verdict on it yet.
- **Upstream:** whether Kodi would take such a workaround upstream was not asked. One rejected workaround elsewhere is not a policy.
