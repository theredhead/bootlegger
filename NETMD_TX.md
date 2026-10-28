# NetMD TX — follow-up scope

Implement after the current Bootlegger SP-transfer failure is diagnosed and verified.

A native macOS background/menu-bar app for NetMD track transfer and disc management:

- Detect attached supported recorders and disc insertion; open the disc's track-list
  window automatically when a disc is inserted.
- Display existing tracks, order, titles, durations, free capacity and recording modes.
- Support drag-and-drop copies to and from the recorder, gated by actual model,
  firmware, disc format and transfer/extraction capabilities.
- Offer original ATRAC preservation on device-to-Mac copies and optional conversion
  to macOS-supported audio formats. Decide decoder dependencies during implementation.
- Reuse Bootlegger's MD recording-mode/encoder options and remembered contextual
  settings. Preserve capability checks, capacity refusal and confirmed disc erase.
- Make progress, safe cancellation, partial completion and recovery information clear.

Share a native device/transfer layer with Bootlegger. Coordinate USB ownership between
apps and windows; do not reset/reopen the recorder merely to poll disc insertion or
track state. A persistent device broker with serialized operations should be evaluated
before adopting the current one-request helper as the final architecture.

No separate project or background app has been created yet.
