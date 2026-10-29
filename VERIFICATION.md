# First implementation verification — 2026-10-28

## Automated native checks

`zsh scripts/test.sh` generates a disposable H.264 movie with a six-second audio
track and tests the same exporter and document classes used by the app:

- Timestamp parsing, millisecond carry, invalid/nonfinite/overflow input.
- Unicode export filename byte limits.
- Invalid ranges rejected; independent overlapping ranges accepted.
- Exports of 0.5–2.25 and 1.5–4.75 seconds read back as 1.75 and 3.25 seconds.
- Output contains AAC audio and no video.
- Song title, album, album artist, per-song artist override, track number/total,
  and JPEG artwork read back from the exported M4As. Genre, date and venue comment
  also appear in the native metadata read-back.
- Project metadata, media and artwork survive a save/reopen round trip after the
  original media is deleted. Bundled media bytes match the original source.
- Distinct documents have independent metadata and AVPlayer instances.
- Metadata edits can be undone and redone.
- Cancelled export leaves no partial album directory.
- Exports inside a `.bootlegger` bundle are rejected.
- Invalid media paths, missing media and unknown project versions produce errors.

`zsh swift-baseline.sh check` passes strict swift-format and SwiftLint checks.
Both Debug and optimized Release apps build with Xcode 27.1. The Release app
was launched and successfully opened the saved demo project. Xcode emits its standard notice that App
Intents metadata extraction was skipped because the app does not use App Intents.

## Checks through the running macOS app

Using only a generated test video and disposable projects:

- Launched the app, opened a project bundle and created an additional project window.
- Edited album metadata, saved, quit/relaunched and reopened the saved project.
- Dragged a song start handle; only that song's start changed.
- Entered a precise timestamp and used Up to nudge it by 0.1 second.
- Captured a video frame as album artwork.
- Deleted a song and restored it with Command-Z.
- Previewed a song and observed playback stop at its 2.25-second end boundary.
- Imported video through the native file picker into a new project, added a song,
  entered metadata, saved a new bundle and exported an M4A into a separate folder.
- Started playback in the newly imported project.

## Still requires user verification

Apple Music import/grouping and presentation of metadata/artwork, listening to real
concert cuts, and performance with full-length videos. See README.md for steps.
Automated checks use generated media; they do not establish compatibility with every
source codec, damaged file, or protected video.

## Video drop and replacement update — 2026-10-28

- Registered movie/video document types for Dock/Open With delivery and routed video
  URLs into the current project (or a new one when needed).
- Added window-wide URL drops and explicit AVPlayerView drop handling so native
  player drops update the document, rather than only changing the visible player.
- Added a shared replacement confirmation for drops, Dock delivery and the file picker.
- Native integration checks pass for initial import, cancelling replacement,
  confirmed replacement retaining metadata/ranges, same-extension dirty tracking,
  and an unreadable replacement preserving the previous media.
- The Debug app builds and strict format/lint checks pass.
- In a disposable project, the running app showed only Bootlegger's controls and
  displayed the replacement confirmation on delivery through macOS's file-opening
  route. Finder-to-window and Finder-to-Dock pointer drags still need user verification.

## Concert editing update — 2026-10-28

- Added document-local S/E marking, Space play/pause, Left/Right ten-second seeks,
  and Shift-Left/Right one-second seeks. Plain keys are ignored during text editing;
  Return commits a field and releases its focus through the editor's submit handler.
- Native tests use an invisible window to check arrow transport, modified menu keys,
  text-editor exclusion and transport resuming after field focus is released.
- Tests verify E creates/selects the next song only after the last listed song and
  before source end, with independent existing ranges retained.
- The editor displays one selected-song timeline, plus measured multichannel audio
  amplitude around the cursor. The display spans ±5 seconds down to ±0.1 second.
- Tools → Prescan Audio Levels fills the whole-concert in-memory cache. Tests check
  whole-source coverage, seeking reuse, save relocation, cancellation and reset.
- Artwork conversion tests cover original aspect ratio, center square cropping,
  cropping existing artwork and importing an image file into project artwork.
- File menu import/export actions use the same document operations as the toolbar.

The integration suite uses generated video and audio. Real-concert waveform
responsiveness, Finder/other-app image dragging and Return focus behavior in the
visible SwiftUI editor remain useful manual checks in Xcode.

## Nondestructive crop editor — 2026-10-28

This replaces the initial center-crop checkbox and buttons. The main window has no
capture/crop buttons or crop checkbox. Double-clicking artwork opens a square crop
sheet with panning, zoom slider/pinch, Reset, Remove Crop, Cancel and Apply. Capture
Frame and crop commands are in the Artwork menu.

Original image bytes and optional normalized crop metadata are saved separately.
Image-file drops preserve exact source bytes, image-data drops use lossless TIFF,
and native-resolution video frames use PNG. Previewing/applying a crop does not
rewrite the original. New artwork clears the crop. Audio export renders the crop
and encodes PNG for transparent corners or JPEG for opaque square corners.

Native tests pass for unchanged original bytes during preview/crop, exact-byte file
import and crop reset, fractional pan/zoom exporting an exact square, original plus
crop surviving save/reopen, and the selected crop being embedded in M4A artwork.
The existing project/export/editor test suite also passes, as do strict format/lint
checks and the Debug app build. Older projects without crop metadata remain readable.

The desktop inspection service stalled during the isolated visual check. The main
window's removed controls/menu were observed; pan/pinch/Apply/Cancel behavior in the
visible sheet remains a manual check in Xcode. Native crop rendering, persistence,
reset and export were verified by the integration suite.

## Live icon and audio recordings — 2026-10-28

The previous icon work produced AppIcon.icns and icon keys in the compiled bundle,
but did not explicitly assign NSApplication's live icon in this manually bootstrapped
AppKit app. Startup now loads that resource, assigns applicationIconImage and redraws
the Dock tile. Source Info.plist also declares CFBundleIconFile/CFBundleIconName.
Development build number is 2 so the About box identifies this build.

Import Recording accepts public.audio as well as movie/video types in the picker,
window drop, player drop and Dock registration. Audio-only sources use native playback,
marking, prescan and export; frame capture is disabled and a clear audio-only placeholder
is shown. Existing projects retain their original JSON videoFilename key for compatibility.
Native tests cover WAV import, audio duration/marking, frame-capture menu exclusion,
trimmed M4A output, measured prescan levels and bundled audio save/reopen after removing
the original source. Common MP3/M4A/WAV/AIFF/FLAC extension routing is checked as well.

## Artwork search integration — 2026-10-28

Adapted the local MacroPad IconPicker/IconSearchPage workflow, also used by the IIgs
builder, into Artwork → Search Artwork. The native search window provides DuckDuckGo
results, image preview, local selection and Use Image. It preserves original bytes
instead of baking in a crop. Search/download requests are cancelled when the window
closes, stale selections are discarded, and remote images have byte/pixel limits.
Native tests cover accepted image data, original-byte preservation, crop reset,
detected filename format, rejection without replacing existing artwork, and the
30 MB selection limit. Live provider results and visible WebKit interaction require
a manual network-enabled check; the automated suite does not contact search sites.

## Search zoom and track deletion correction — 2026-10-28

Track rows previously used array-index-backed bindings. Those bindings could outlive
an array slot during deletion/reordering, and the timeline retained an indexed binding
to the selected song. Rows now iterate value snapshots, bind by UUID on every access,
and ignore late writes to deleted songs. Timeline/audio-level drawing uses song values.
Selection repair runs after project storage changes, outside the publisher's willSet
notification. Deleting the selected track chooses a surviving neighbor, or clears the
selection for an empty list.

Regression tests pass for first/middle/last/only-track deletion, repeated deletion,
late field commits, bindings after reorder, undo/redo restoring the final song, and
SwiftUI list/timeline/audio graph reconciliation in an invisible hosting window.

The artwork search now includes a square pan/zoom preview, visible 0.1–20× slider,
pinch zoom, Use This Crop and Use Full Image. Applying a crop preserves original data
and stores normalized crop metadata. New results reset the preview. Native tests check
search preview pan/zoom, reset, and transfer of original data plus crop into the project.

## Editing focus, range ordering and filename metadata — 2026-10-28

Main-window string fields now use native commit-aware text fields. The document window
handles Return/keypad Enter/Escape before transport filtering, explicitly ends editing
and becomes first responder. Clicks outside editable fields release focus; hit-testing
uses superview coordinates so flipped SwiftUI/AppKit containers work correctly.
Unselected song rows show plain text instead of active editors.

All row/timestamp/timeline bindings and S/E mutations share identity-based range
validation. Reversed, equal, negative/nonfinite and out-of-source boundaries are rejected;
valid existing ranges and independent overlaps are retained. Timestamp fields display
the accepted stored value after rejection. EOF cannot create a zero-length song.
Older invalid saved ranges are reported on load and can be repaired without blocking
metadata edits.

Empty album title/year fields are seeded only after successful import. Filename title
cleanup normalizes separators, preserves dotted acronyms/mixed-case names, and applies
title casing. The last standalone year from 1900–2099 seeds a blank Year field. Existing
user metadata is never overwritten. Tests cover these defaults, replacement preservation,
Return/Escape release, outside clicks with flipped coordinates, and range rejection.

## Row selection, artwork padding and window sizing

Native regression checks cover row padding and control hit regions, text-focus handoff, hidden/deleted row guards, zoom-out black padding, transparent PNG corners, crop orientation, radius defaults and persistence. The upper player/metadata section is capped at metadata content height; surplus window height goes to the track list. Visible resizing and crop interaction remain manual Xcode checks.

## Export preparation and strategy preferences

Export-plan regression tests cover all-selected defaults, summed durations (including
overlap), deselection, reordered export snapshots, preservation of the saved project,
empty totals, and routing the export command to preparation without writing files.
The native preparation sheet uses list drag reordering and a split menu action;
Settings stores the default strategy in UserDefaults. MD/CD actions show placeholders.
Manual UI checks: drag selected and deselected rows, cancel the sheet/destination
panel, change Settings and reopen export, invoke each strategy, and verify exported
track numbers/order in Apple Music. No hardware writing is implemented.

## File encoding options and filename tokens

Native tests export and reopen AAC, ALAC, WAV, AIFF, and CAF, checking codec,
48 kHz sample rate, 24-bit PCM, trimmed duration, and M4A title metadata. Existing
AAC export tests also verify album tags, track numbers and binary artwork. Tests
cover preference defaults, filename expansion and sanitization, collision rejection,
and native token-field clipboard parsing/pill styles. Build and strict style checks
pass. Visible token insertion, dragging/reordering, editing literal separators, and
Settings-to-export overrides remain manual UI checks. WAV/AIFF/CAF tag writing is
not implemented and is stated in the UI.

## Native NetMD export

- Vendored netmd++ revision and dependency release checksums are recorded. Helper
  build, source/license packaging and app signing are checked by the Xcode build.
- Swift tests cover cluster-rounded capacity boundaries, LP factors, write protection,
  insufficient space, unsupported modes, 255-track limits, independent preferences,
  helper progress/error propagation, malformed command rejection, and read-only USB
  discovery returning a structured result/error.
- Native synthetic TOC test splits one recording into unequal tracks and verifies
  contiguous, unique coverage of every original audio group, titles, track count,
  and rejection of a cyclic fragment chain. This does not establish hardware safety.
- Live read-only discovery returns a structured error when no recorder is enumerated. An
  SDK weak-import issue in libusb's pipe2 feature detection was caught by this probe;
  the build explicitly selects its portable pipe/fcntl path for macOS 15 deployment.
- After reconnecting the USB cable, live read-only discovery identified a Sony MZ-RH1
  with an empty writable disc, 4,499 SP-equivalent seconds available, and stable repeated
  snapshots. Its capability report disables gapless SP and on-device LP encoding.
  USB writes, disc erase, title encoding, accuracy of capacity during recording,
  device-specific gapless operations, cancellation and playback remain unverified.
  No tracks were written or erased during diagnosis. Test with a disposable MD first.

Manual checks: attach one recorder, Refresh, compare displayed capacity against the
recorder, choose an oversized selection and verify refusal, toggle write protection,
confirm/cancel erase and verify capacity refresh, write SP tracks in custom order,
verify titles and audible boundaries. On supported hardware, test gapless SP on a
blank MD and check retained recovery TOCs. On a compatible deck, test LP2/LP4. Disconnect
or swap a disc between review and action and verify refusal. Attach two recorders
and verify that the app asks for only one. Completed tracks may remain after failure;
never assume that cancellation rolls back the disc.

## Recorder detection diagnosis

The initial macOS USB Host inventory contained only a hub and AV adapter. After
reconnection, the Net MD/Hi-MD device appeared and the helper read it successfully.
Discovery now distinguishes no supported USB device from an identified recorder that
cannot be opened or whose disc cannot be read. Multiple recorder refusal remains.
Build and regression suite pass, including read-only discovery on the connected RH1.

## RH1 false recorder-change correction

Repeated read-only RH1 probes reproduced alternating USB addresses (`2:2` and `2:4`)
with identical disc contents. The backend resets/reopens USB, so that temporary
address cannot identify a recorder. The snapshot now uses vendor/product IDs, USB
bus and physical port chain, retaining all disc-content/capacity/protection fields.
Native tests verify address reassignment is ignored, physical-port/model changes are
detected, and missing port topology fails closed. Three live probes then returned
identical fingerprints on the connected RH1. No disc writes or erases were performed.

## Export-only options and attached-device strategy selection

The export Preferences/Settings UI and saved strategy preference are removed. File
and MD settings are edited in export preparation popups and remembered automatically.
MD is absent from the export menu without an attached supported recorder. On opening
preparation, MD is the default when attached; otherwise Files is the default. Read-only
USB enumeration updates attachment state every two seconds while the sheet is open,
without opening/resetting a recorder or reading its disc. Device presence is separate
from readiness/capacity: a connected recorder without a writable disc still reveals
MD, but cannot write until preflight succeeds. Manual strategy changes persist while
the attachment state remains unchanged.

Tests cover menu inclusion/exclusion and attached/unattached default selection. The
new enumeration command detects the connected Sony MZ-RH1 by its stable physical
port identity. Visible connect/disconnect menu behavior remains a manual UI check.

## Unified export options button

The preparation footer now orders Cancel/Stop, the Options gear, and the split export
button. One popover switches between file settings, MD settings/device controls,
and CD placeholder information. Method selection only changes the selected method;
no export or placeholder alert is invoked by selection. Visible footer layout and
popover switching remain manual UI checks.

## NetMD error -8 and optional software ATRAC

Reproduced macOS AVAssetWriter WAV output containing JUNK before fmt, FLLR padding,
and WAVE_FORMAT_EXTENSIBLE (0xfffe). The backend accepts only classic PCM with fmt
first. NetMDPCMFile now rewraps staging audio losslessly into a classic 44-byte-header
WAV. Tests check byte-for-byte PCM preservation, duration, idempotence and rejection
without input replacement. This fixes the file rejection before USB transfer.

The user authorized testing on a throwaway MD. Hardware tests on the connected
MZ-RH1 successfully wrote and read back three short tracks: recorder SP, software
ATRAC3 LP2, and software ATRAC3 LP4. USB payloads were 354,328 / 33,432 / 16,728 bytes,
respectively. The three test tracks remain on the disc; no erase was performed.
Reported track lengths were 2.00 / 2.01 / 1.85 seconds for a 2-second source. LP4's
shorter reported duration is a known open hardware timing/playback verification item;
LP4 is marked experimental in the popup. No audible playback verification was done.
Gapless and software ATRAC1 upload remain untested on physical supported hardware;
the RH1 reports those paths unsupported and the UI/preflight refuses them.

ATRACDEnc is bundled and built from pinned source, with static PCM-only libsndfile.
Tests encode ATRAC1 AEA and LP2/LP4 ATRAC3 RIFF, check format/block alignment and payload
reduction, and exercise device capability rejection. Both MD mode and encoder choices
persist. Capacity reservation now uses the exact cluster duration and an extra cluster
per recording to cover observed device/codec allocation padding. No transfer-speed
multiple is claimed from these short tests; only USB payload reduction was measured.

## Longer SP failure diagnosis — not yet resolved

A user export with default recorder/SP settings failed with generic -4 after the WAV
fix. A subsequent read-only probe returned -4 while requesting the inserted disc's
track count; the planned 30-second transfer did not start. The next live USB probe
was blocked because automatic approval review could not complete due to account usage
limits. No additional test tracks were written during this diagnosis.

The native backend now preserves underlying sendTrack/commitTrack return codes,
instead of wrapping every failure as -4. The app retains stderr in per-operation
logs under the temporary BootleggerNetMDLogs directory and includes a bounded tail
of WARN/CRITICAL details plus its log path in the error. A standalone offline fixture
checks that the original code, detailed cause and retained log reach the caller.
Full SwiftUI build/tests could not run inside the sandbox because the Swift macro
plugin is unavailable there; native source compilation and offline native TOC tests
remain possible. Longer physical transfer validation is still required.

### Continued failure diagnosis

Approval review subsequently recovered. Detailed read-only traces showed capacity
queries accepted while the audio-contents/track-count query returned REJECTED (0x0a).
Explicit descriptor open/close handling was added, matching the reference protocol,
but that alone did not restore the current recorder session. The library also reset
USB every time it opened the device; this was removed so inspection cannot reset an
active recorder. The user reported only the charging light and no button/display
response; the RH1 then disappeared from the macOS USB Host inventory. A physical power
cycle was requested using Sony's manual, page 70. The longer SP transfer has not run
and this failure must not yet be considered fixed. Backend errors now always include
the retained diagnostic log path, even if no CRITICAL/WARN detail was emitted.

### SP transfer failure reproduced and corrected

After the RH1 returned on another hub port, the 30-second SP test reproduced an
80-second timeout on its first 1,048,576-byte host USB request, followed by device
loss. The preserved underlying error is USB (-1); the earlier generic -4 masked it.
The native adapter now caps host writes at 16 KiB while preserving the encrypted
logical packets and audio bytes. It handles short successful writes, bounded empty
interruptions, timeouts and zero-progress responses without looping forever.

The identical 30-second transfer then succeeded through the same hub and cable.
A further two-track batch (180-second SP plus 2-second SP) succeeded, transferring
31,752,216 bytes for the long track, then advancing to and completing the second.
Readback shows three tracks with titles and durations 30 / 180 / 2 seconds. The RH1
remained visible and readable afterward. These three test tracks remain on the
throwaway disc; no erase was performed. No full 41-minute concert has been written
or playback checked by ear.

Native regression tests cover a >1 MiB logical write fragmented into bounded requests,
short writes, timeout propagation and zero-progress termination. The full offline
export/document/encoding suite passes. The native build cache now invalidates objects
when included vendor headers change. NetMD TX's follow-up scope is in NETMD_TX.md.

Incremental signing correction: declared both helper executables and the bundled
source directory as outputs of the native build phase. Without these outputs, an
incremental build could replace helpers/resources without rerunning the outer app's
CodeSign task. Deep strict signature verification is checked after incremental builds.

Export progress: while exporting, verify that the track list and preparation controls
are replaced by a compact progress view and Cancel button. File preparation and MD
USB transfers should advance within each track. Successful exports close the sheet;
errors and cancellation retain the selected tracks and order. MD cancellation finishes
the active recording safely before stopping.

Artwork search: without a selected image, verify the preview shows a photo icon
and “No image yet” instead of a black crop. Type a query and pause for half a second
for automatic search. Rapid edits should cancel the previous timer/navigation;
Return and Search should run immediately without a second delayed request. Clearing
the query should clear selection/results and issue no search. Close the window or
choose a local image during the debounce and verify no delayed search clears it.
Older navigation errors/results must not replace the current query's state.

Startup acknowledgements: launch Bootlegger and verify its centered, appearance-aware
splash closes after approximately two seconds without blocking startup. About
Bootlegger should retain linked author credits, version/build and license information.

Updated acknowledgements layout: splash should show a large app icon, app name and
a short reference to the About credits, with no vendor list. It should still close
after two seconds. About should show all linked project names, author credits,
version and license text at once, with no scrolling. The content-sized Bootlegger
About layout was rendered and checked for unclipped views.

Hardware playback: the user confirmed successful playback of the recorded albums
on real hardware after resolving the playback device issue.
