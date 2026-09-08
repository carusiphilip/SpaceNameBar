# Local validation — 8 September 2026

Environment: Apple silicon, macOS 26.5.2, Swift 6.3.1, Command Line Tools (no full Xcode installation).

This is a chronological record. Earlier entries describe earlier releases; see Version 1.3 below and `HANDOFF.md` for the current behavior and remaining limitations.

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

## Version 1.2.1 — F3 recovery and redraw

- Reproduced missing labels by restarting the app while Mission Control was already open: event registration succeeded, but there was no new opening event and no overlay was created.
- Moved observer startup to applicationDidFinishLaunching and added recovery for an already-open Mission Control view, with two bounded startup retries.
- Explicitly redraw when showing a previously hidden overlay; avoid repeatedly setting an unchanged window frame and ordering the same visible panel forward.
- Live diagnostic run confirmed recovery without a new opening event, then label drawing through repeated Mission Control enter/exit cycles.
- Visually verified desktop names and window titles in the actual overlay after the fix. No screenshots or window titles are included in this repository.
- Core and startup checks passed. App snapshots and preferences were not modified by this fix.

## Version 1.3 — placement and recurring F3 recovery

- F3 labels recurred as missing after the earlier fix. Added fresh panels for every opening, event-driven shortcut recovery, and a shallow one-second check for missed Dock events. Live traces demonstrated recovery before an opening notification arrived. The user confirmed the labels remained visible after this update.
- Implemented window snapshots and verified moves using the bridged SkyLight operation with system security unchanged.
- A disposable window moved to another ordinary desktop and back, with both memberships checked.
- Two disposable windows restored to different desktops through the real delayed startup controller under a simulated login. The check also covered a completed app-launch receipt with incomplete placement, plus same-login suppression.
- Core checks cover new numeric window IDs, unique document/title matching, ambiguous duplicate rejection, Terminal slots, old snapshot migration and old receipt migration. Existing app-launch integration checks still pass.
- A live Terminal restore exposed an inactive-desktop issue: Accessibility omitted windows after placement, causing early retries to create extra windows. WindowServer inventory now covers inactive ordinary and full-screen desktops. Existing extra windows are not automatically closed.
- Full-screen reconstruction, identical document sessions, running shell jobs, exact window contents and a real reboot are not claimed as verified.
