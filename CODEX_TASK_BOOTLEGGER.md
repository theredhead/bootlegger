# Bootlegger — Codex implementation brief

Repository: https://github.com/theredhead/bootlegger

## Mission
Build a small, dogfooding-first, open-source **native macOS Swift** app that turns a locally available concert video into a folder of individually trimmed, properly tagged **AAC/M4A** songs that Apple Music can import as an album.

Prioritize a working, pleasant desktop utility. Avoid speculative abstractions, backends, accounts, analytics, cloud services, or unnecessary dependencies. Use SwiftUI and AVKit/AVFoundation, with AppKit when it improves desktop interactions. No FFmpeg or MP3 requirement for the MVP.

## User experience
- Open a local video and play/pause/scrub it precisely.
- Show a timeline with simple click-to-add and drag-to-adjust track boundaries. Make precise adjustment easy, including keyboard nudging if practical.
- Each song has **independent start and end times**; gaps and overlaps are allowed. Do not model songs as only contiguous shared cut points.
- Display and edit a track list with titles and time ranges; select a track to preview its boundaries.
- Set album-wide metadata once (album title/concert name, album artist, optional date/year, venue, genre as practical), plus per-song metadata (title, track number, optional artist override).
- Capture a frame from the source video for album cover art; ideally allow individual track artwork overrides, but album artwork alone is sufficient for the first vertical slice.
- Save/reopen an editable project as a self-contained macOS document bundle containing a copy of the opened video and all collected project metadata, including track ranges, album/song metadata, and captured artwork. Preserve the original source video unchanged.
- Support multiple project windows open at the same time, each with independent document state, playback, and save/load behavior.
- Exported audio files live outside the project bundle and are not part of the saved project.
- Export a directory of numbered M4A tracks, with audio trimmed to each song's time range and embedded metadata/artwork compatible with Apple Music.

## First milestone (build this before polishing)
1. Create a buildable Xcode macOS project.
2. Import a local concert video and seek/play it.
3. Define two or three tracks with independently editable start/end timestamps.
4. Enter album title/artist and per-track titles.
5. Export M4A files with correct trimming and embedded metadata.
6. Document precise manual steps for verifying exported tracks in Apple Music and any uncertainties. The user will perform Apple Music import and metadata verification.
7. Save and reopen self-contained project bundles, and allow more than one project window to be open simultaneously.

## Acceptance criteria
- Project builds and launches on macOS; README includes build/run instructions.
- Scrubbing and track-boundary editing are usable, not just static placeholders.
- Independent, overlapping song ranges are supported.
- Project state survives save/reopen, including the bundled video, track ranges, album/song metadata, and artwork. Projects remain usable after the original video is moved or removed.
- Projects are macOS document bundles and support multiple simultaneous windows with independent state.
- Exported audio files are saved outside the project bundle and are not included in the project.
- Export does not mutate the source video.
- Exported filenames are orderly and metadata includes album, album artist, song title, artist and track number; cover art is embedded once artwork capture is implemented.
- Bad ranges, unavailable source files, and export failures show useful errors.
- Avoid silently claiming metadata works if AVFoundation export omits a field: test or document limitations and use a focused native alternative where needed.

## Not in MVP
- Automatic song-boundary suggestions / audio analysis
- Fade in/out controls
- YouTube downloads, URL importing, chapter/setlist import
- Metadata lookup services
- MP3, FLAC or ALAC export
- Batch processing, licensing, signing or notarization pipeline

## Design notes
A good player, straightforward timeline and editable metadata are the product. A waveform is optional for MVP; do not block the first export on generating one. Avoid overengineering. Prefer incremental, testable vertical slices. Use native system controls where appropriate.

Brand: **Bootlegger**. Possible later icon: an old-fashioned cowboy boot with a vinyl record motif. Icon design must not block functionality.

License intent: MIT; include LICENSE if not already present. Inspect the existing repository first and preserve existing files and conventions.

## Instructions to Codex
Work in the cloned repository. Start by inspecting its contents and creating the smallest functional implementation. Implement as much of the first milestone as feasible, run available build/tests, and report what works, what remains, and any verification steps. Keep changes committed or ready for review; don't add out-of-scope features without asking.
