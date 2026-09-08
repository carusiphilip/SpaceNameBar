# Local validation — 8 September 2026

Environment: Apple silicon, macOS 26.5.2, Swift 6.3.1, Command Line Tools (no full Xcode installation).

Passed:

- Debug and optimized release builds.
- All eight dependency-free core checks (`swift run SpaceNameCoreChecks`).
- Bundle property-list validation and ad-hoc signature verification.
- Live Space detection with both ordinary and full-screen Spaces, stable-format UUIDs, and one active desktop identified.
- Live detection returned a different active desktop after desktop UI interaction.
- Installed app launched successfully as an agent from `~/Applications`.
- Idle process sample: main thread waiting in the event loop, approximately 15 MB physical footprint and a 0.0% CPU snapshot. These are observations, not a benchmark guarantee.

Not verified end to end in this session:

- Visual popover interaction, typing/Return, and the displayed title during switching: desktop automation timed out when selecting the menu-bar-only app.
- Actual logout/reboot persistence, login-item startup, physical multiple-display behavior, and Mission Control reordering. Core checks simulate identity changes and test persistence in an isolated UserDefaults domain.

The normal app does not save or print a diagnostic log. Machine-specific Space IDs, desktop names, screenshots, and process samples are not part of this repository.

## Version 1.1

- Added continuous Desktop N numbering including full-screen Spaces.
- Added optional Mission Control desktop-name and window-title overlays, gated by Accessibility permission.
- Added a coordinate conversion/placement check for multiple display arrangements (nine core checks total).
- After Accessibility was granted, the installed app reported 17 desktop labels and changing counts of 2–3 window titles through its live UI. Both F3 switches were on, confirming permission recognition, event delivery, and label generation. The menu was also visually inspected. Exact overlay alignment and click-through behavior have not yet been visually verified in Mission Control.
- In version 1.1, workspace snapshot/restore was unimplemented; launch at login only started SpaceNameBar.

## Version 1.2 — saved startup apps

Passed:

- Core startup persistence, deduplication, owner-only file permissions, retry limits, failure reporting, same-session suppression, simulated new-boot restore, crash attempt limits, snapshot backups and corruption detection.
- Real launch integration using a disposable native test app: launch, skip while running, terminate only the test app, and relaunch for a simulated new login.
- The production startup controller's delayed automatic path, invoked through the same eager entry point used at app startup, without opening a menu. A second controller in the same simulated session did not launch again.
- Reading the real login session identifier and kernel boot timestamp.
- Release build/signature verification; installed app captured the current app list and custom names.
- A fresh process reloaded that snapshot and confirmed startup restore and the login item were enabled. Saved names were compared against UserDefaults and matched exactly; snapshot permissions were verified.

Not claimed or tested: a real reboot/logout, every third-party app's session restoration, exact window/Space placement, recreation of full-screen/Split View layouts, or resumption of terminal jobs. This release restores app launches and keeps name backups; it does not implement exact window layout restoration.
