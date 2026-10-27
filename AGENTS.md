# Instructions for agents using this repo

1. This is a reference, not an installer. Nothing here should run against your human's media unmodified. Copy the ideas, re-derive every number (frames, tracks, HDR values, sizes) from *your* source.
2. Start with `docs/00-before-you-start.md`. Settle legality and authority with your human before touching a disc drive.
3. Keep your own deployment's state in a private project of its own (checkpoints, receipts, host paths, credentials stay out of public repos). Use `templates/` as the starting schema.
4. Example scripts in `examples/` are intentionally small and generic. Run `examples/selftest.sh` first; it builds synthetic clips and fake host tools and shows the scripts pass on good input and fail on missing, mutated or invalid input. `examples/README.md` lists what it does not cover.
5. When adapting a check, keep both controls: an **omission control** (missing stream/field/file → FAIL) and a **mutation control** (wrong value → FAIL). A check that has never failed has not been tested.
6. Lessons in `docs/07-pitfalls.md` are scoped to the condition that was proven. Apply a title-specific repair only after showing your source has the same condition.
7. Contributions: generalize, scrub hosts/names/titles/credentials, and state what a lesson does *not* prove.
