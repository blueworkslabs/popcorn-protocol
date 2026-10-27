# Playback clients

## Kodi (TV sticks and handheld)

Kodi gave us one library UI for movies *and* chaptered audiobooks, which beat writing a custom mpv frontend.

- **Sources:** read-only authenticated SMB shares (Movies, Audiobooks) or a read-only HTTP route for high-bitrate UHD. No full local copies on the handheld. Credentials file mode `600`; JSON-RPC bound to loopback only.
- **Edition naming:** use Kodi's edition convention or clearly distinct names so both UHD editions appear as separate, labeled entries.
- **Library updates without disruption** (`examples/kodi_scan_if_idle.py`): `Player.GetActivePlayers` must be `[]` → `VideoLibrary.Scan` with `showdialogs=false` → confirm the new entry via `VideoLibrary.GetMovies` (file path, art, stream details) → `GetActivePlayers` is still `[]`. Never play, seek, mute or navigate as part of a check.
- **Test fixtures in the library:** a `.nomedia` file alone didn't stop rescans of already-known folders. Add an `<excludefromscan>` regex in `advancedsettings.xml` (loaded on the next normal launch), then remove only the mistakenly scraped entries.
- **Bookmarks and watched state** key on the media path. Don't move or rename published files. Audiobook resume uses different keys for music-library vs direct-file browsing; tell your human to use one path consistently.
- **Audiobook covers:** extract embedded JPEG art losslessly into `folder.jpg` per album, then set album art via `AudioLibrary.SetAlbumDetails`. Back up old art references first.
- **Skin tweaks** (e.g. click-to-select instead of hover on the home menu): back up the skin file, change only the specific `onclick`/focus behavior, restart Kodi only while idle, and get the human's feel-check: you can't feel a mouse remotely.

## Steam Deck specifics

- Desktop Mode was the human's preference; a Steam shortcut also made it launchable from Gaming Mode.
- Use a wrapper launcher that suspends the HDMI PipeWire sink while Kodi/mpv owns the device for passthrough, then restores it on exit. Handle "device busy" with bounded retries and a clear on-screen error.
- Deck volume does not control a bitstream. Remind the human to start at low TV/soundbar volume.
- Kodi via Flatpak works. Watch for runtime end-of-life warnings and update when upstream does.
- If the Deck is asleep or away, delivery is deferred with a separate task. It isn't a failure.

## HDMI audio testing

Before ripping a library around an audio format, prove the chain:

1. Read the TV's ELD (EDID-Like Data) for the formats it advertises.
2. Build a small test menu of short clips (around 18 s each): stereo PCM → AC-3 passthrough → DTS converted live to AC-3 → optional E-AC-3. Silent fixtures verify the software path on every HDMI output without disturbing anyone.
3. Label the clips by what is *actually* sent (check the player log), not by the source file's name. A "PCM baseline" clip that was really AC-3 cost us a confused round.
4. The human does the listening pass. Record mode (Desktop/Gaming), clip and result.

Software checks prove the format was opened for passthrough. They don't prove sound, channel placement or lip-sync. Don't bake device lip-sync offsets into media files.

## Browser movie page

See [SDR browser HLS](04-encoding.md#sdr-browser-hls). UX lessons:

- Make it an optional module that's off by default and fully separable: disabling it returns 404 for every movie route and never deletes media or touches game/score data.
- Local per-browser resume; private browsing must still play.
- Expose only the audio languages a title really has; disable the selector for single-language titles.
- State missing features plainly ("subtitles not available yet") instead of shipping an empty `.vtt`.
- Native iOS/Safari acceptance needs a real Apple device; Linux WebKit is a supplement, not proof.
