# Before you start

## Legality

Ripping commercial Blu-ray/UHD discs usually means bypassing copy protection (AACS, AACS 2, BD+). In many jurisdictions that is restricted even for discs you own and for private use (for example the DMCA anti-circumvention rule in the US, or the EU copyright directive as transposed in member states). This repo describes a workflow. It ships no keys or decryption tools and does not tell you where to get them.

Raise this with your human before the first rip. They decide whether it is lawful where they live; you don't decide it for them, and you don't quietly download keys or flash drive firmware to get around a failure.

Never share ripped media or expose it to the internet. Everything in this playbook stays on the home LAN.

## Scope questions to settle first

Ask once, write the answers down (they become retained decisions):

- **Editions:** original-quality archive only, or also a streaming edition? (Recommended for UHD: both.)
- **Content:** 2D only, or 3D too? Extended cuts? Which audio languages and subtitles?
- **Clients:** TV sticks, handheld, browser/phone, a projector? Which one is the "real" movie screen?
- **Audio chain:** TV speakers, soundbar via ARC/eARC, AVR? Which formats does the chain actually decode (PCM, AC-3, E-AC-3, DTS, TrueHD/Atmos)?
- **Storage:** which disks, which are disposable scratch, which hold backups you must not eat into?
- **Concurrency and heat:** can jobs overlap? What sustained CPU temperature is the human comfortable with?
- **Maintenance:** may the OS install updates or restart services on its own? (After losing a multi-hour extraction to an automatic service restart, our answer became: notify only, install manually.)
- **Quiet hours / playback priority:** jobs must never interrupt someone watching.

## Authority

- Documentation or planning work is not permission to pause jobs, restart services, publish media, delete files or install updates.
- A permission is scoped. "You may discard that interrupted partial rip" does not extend to finished media or completed encodes.
- Parallel jobs that were allowed once under measured headroom are not blanket permission to exceed caps later.
- Record each decision with a date and the request that granted it. Later explicit instructions supersede older ones.

## What only the human can verify

Lip-sync, audible quality, surround placement, "does the remote feel right", and whether a visual glitch is acceptable. Ask for a targeted spot-check ("watch 2 minutes around 1:12:30"), record exactly what they checked, and never claim more than that.

Do not make the human run mechanical tests (pressing play on twenty clips, typing bursts). Script those and bring them only the judgment calls.
