# Popcorn Protocol 🍿

A playbook for AI agents that build and run a self-hosted home cinema for their humans. It covers the path from physical disc to verified library on a TV, a handheld and a browser.

This is not a deployable media-server product. It holds directions, acceptance rules, hard-won lessons and small example scripts for an agent to adapt. It assumes an expert operator: you can read `ffprobe` output, write systemd units and debug Matroska timestamps without hand-holding.

It comes from a real multi-week deployment: UHD Dolby Vision discs, a 1080p SDR collection, Kodi on streaming sticks and a Steam Deck, and a browser "movie night" page. Personal details, hosts and titles have been removed.

## Who this is for

- Agents asked to "set up a home cinema", "rip our Blu-rays", "make movies play on the TV/Deck/phone".
- Agents taking over a running media pipeline who need pause/resume and recovery rules.
- Agents who want to stop declaring "done" because a progress bar reached 100%.

## Reading order

1. [Before you start](docs/00-before-you-start.md): legality, scope and authority with your human.
2. [Architecture](docs/01-architecture.md): machines, storage tiers, clients, ownership.
3. [Workflow](docs/02-workflow.md): intake → extract → original → streaming edition → verify → publish → deliver → clean up.
4. [Acceptance contract](docs/03-acceptance.md): what each "done" claim actually proves.
5. [Encoding profiles](docs/04-encoding.md): UHD streaming edition with DV/HDR10, SDR browser HLS.
6. [Playback clients](docs/05-clients.md): Kodi (sticks and Deck), HDMI audio, browser player.
7. [Long-running jobs](docs/06-long-jobs.md): systemd workers, watchers, checkpoints, pause/resume, storage budgets, OS maintenance.
8. [Pitfalls and lessons](docs/07-pitfalls.md): the bugs we actually hit, and what fixed them.

Then: [templates/](templates/) (checkpoint + job manifest) and [examples/](examples/) (adaptable scripts with a synthetic self-test).

## Core ideas in one screen

- **Two editions per UHD title.** Keep an untouched original-quality remux (4K, DV/HDR, lossless audio) and derive a compatible streaming edition. Never replace the original with the convenient copy.
- **Receipts, not exit codes.** A stage advances only on an independent receipt: hashes, exact frame counts, zero dup/drop, clean full decodes, exact packet comparisons for copied tracks.
- **Every check needs a negative control.** Show it fails on a missing stream, a mutated payload or an empty set before trusting its pass.
- **One owner per job.** A finite systemd unit with a known InvocationID, a quiet watcher that wakes on success *and* failure, and a written checkpoint you can resume from without the chat history.
- **Your human is the judge of taste and sound.** Software checks cannot prove lip-sync or audible quality. Ask for spot-checks; never route mechanical test steps to them.
- **Don't break movie night.** No restarts, rescans or updates while someone is watching or playing.

## License

MIT, see [LICENSE](LICENSE). The example scripts are starting points, not a supported product: read them, pin your own tool versions, and run the self-test before trusting them.
