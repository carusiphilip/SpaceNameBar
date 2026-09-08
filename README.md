# SpaceNameBar

A small native macOS menu bar app that gives each desktop a name: **💬 Agent Runners**, **Documentation**, **Builds**, or whatever helps you find your place.

## Use

1. Open `SpaceNameBar.app` from your Applications folder.
2. Click the desktop name in the menu bar.
3. Enter a name and press **Return** (or click **Save Name**).
4. Switch desktops normally. The menu bar updates to that desktop's saved name.

**Reset Name** restores the default label. Saving an empty name does the same. Emoji are supported; names are limited to 80 characters. Short names fit best on crowded menu bars. Enable **Launch at login** in the popover if desired. There is no Dock icon or main window; quit from the popover.

Every Space—including a full-screen app—uses one continuous default sequence: **Desktop 1, Desktop 2, Desktop 3…**, following the Space list order. A saved custom name overrides that default.

## Mission Control (F3)

The menu has separate **Desktop names** and **Window titles** switches. Click **Enable Accessibility…**, then enable SpaceNameBar in System Settings → Privacy & Security → Accessibility. Reopen the menu after granting permission.

The app draws click-through labels at the positions exposed by Mission Control: custom names (or Desktop N) on Space thumbnails, and existing window titles on individual window previews. It does not change other apps' titles or modify the Dock. Windows remain clickable and draggable through the overlay.

**This integration is experimental.** Live Accessibility event delivery, label generation and visible labels after repeated Mission Control openings have been checked. Exact alignment across other display arrangements and click-through behavior still need broader verification. Mission Control's accessibility structure is undocumented. Labels are shown only for thumbnails the Dock exposes with usable positions; unsupported/missing window titles cannot be reconstructed. The app doesn't guess a Space's name if thumbnail counts do not match. Full-screen Spaces have the same Desktop N naming as ordinary Spaces.

The overlay detects Mission Control even if it was already open when SpaceNameBar started or updated. It redraws whenever shown. A shallow once-per-second check recovers missed Dock events when F3 labels are enabled. F3/Control-Up input is observed without consuming events or recording typed text. Each opening creates fresh overlay panels. While Mission Control is open, a 200 ms timer follows animation and hover changes; it stops when Mission Control closes. The normal menu bar feature does not need Accessibility.

## Build and install

Requires macOS 13 or later and Swift 6 or later (Xcode or Apple's Command Line Tools). No third-party dependencies.

```sh
./scripts/install.sh
```

This builds a release app, ad-hoc signs it, copies it to `~/Applications/SpaceNameBar.app`, and opens it. For updates, quit the existing app first. Build only with `./scripts/build.sh`. The bundle is in `dist/SpaceNameBar.app` and is built for the current Mac's architecture.

The local build does not need a paid Apple developer account. It is not Developer ID signed or notarized for distribution to other Macs.

## How detection works

SwiftUI `MenuBarExtra` with `.window` style provides a dropdown that supports a real text field. `LSUIElement` keeps the app out of the Dock. The app listens through `NSWorkspace.shared.notificationCenter` for `activeSpaceDidChangeNotification`. It also refreshes on wake, session activation, display changes, app activation (for display focus), and menu opening. Each system event has one cancellable 350 ms follow-up to handle transition timing. The normal Space detection path has no periodic polling, input monitoring, background network traffic, or subprocess. The optional F3 overlay observes Dock Accessibility events, checks for a missed opening once per second, and refreshes geometry only while Mission Control is open.

Apple's public notification contains no Space identifier. A small isolated adapter dynamically resolves three **undocumented, read-only SkyLight functions**:

- `CGSMainConnectionID`
- `CGSCopyManagedDisplaySpaces`
- `CGSCopyActiveMenuBarDisplayIdentifier`

It reads the current desktop and its UUID. This read-only Space detection uses no injection, workspace manipulation, Accessibility permission, Screen Recording permission, root privileges, or SIP changes. The optional F3 overlay separately requires Accessibility permission to read the Dock's thumbnail geometry and titles. Missing functions or unrecognizable data produce an unavailable message and disable naming instead of assigning a label to an arbitrary desktop. Private APIs can change in a macOS update; this is a personal utility, not an App Store submission.

References: [Dock Mission Control event declarations](https://github.com/asmvik/yabai/blob/master/src/mission_control.c), [Mission Control accessibility hierarchy](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua), [Apple's notification documentation](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification), [CGS display declarations](https://github.com/NUIKit/CGSInternal/blob/master/CGSDisplays.h).

## Persistence and displays

Labels live locally in `UserDefaults`, domain `com.carusiphilip.SpaceNameBar`, key `spaceLabels.v1`. The map uses Space UUIDs, **not numeric IDs or desktop positions**. Numeric IDs can change across sessions. Reordering an existing desktop preserves its label; labels remain stored across app exits, logout, and restart. If macOS deletes/recreates a Space or assigns it a new UUID, it is a new desktop and needs a new name. Full-screen Spaces can also be named, but macOS may recreate them when apps reopen. Old mappings are retained so a temporarily absent Space can recover its name.

With multiple displays, the shared menu bar title follows the active menu bar display; opening the editor targets the display under the pointer. macOS mirrors a single `MenuBarExtra` across screens, so this version does **not** render different simultaneous titles on each monitor. Moving only the pointer, without changing Spaces, activating an app, or opening the menu, does not trigger a refresh. With unified Spaces, a single visible desktop is supported even when macOS identifies the display as `Main`.

The editor rechecks the visible Space before saving. If it changed mid-edit, the old name is not written to a different Space.

## Verification

```sh
swift run SpaceNameCoreChecks
./scripts/check-startup.sh
./scripts/build.sh
./dist/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --diagnose
```

The dependency-free checks run with Command Line Tools alone. They cover UUID identity across reordering/new session IDs, continuous full-screen/desktop numbering, multiple displays, unified displays, malformed data, current-Space resolution, independent persisted labels/reset, Unicode limits, and overlay coordinate conversion across displays. The diagnostic command prints Space metadata only and exits; it does not save labels.

Manual checks for a macOS update:

1. Name two desktops differently and switch between them using your usual gestures or shortcuts.
2. Quit/reopen the app and confirm both labels remain.
3. Reorder a named desktop in Mission Control and confirm its label follows it.
4. Check full-screen Spaces, sleep/wake, and any external displays you use.
5. Enable launch at login, log out/in, and confirm startup. If macOS requests approval, allow SpaceNameBar in System Settings → General → Login Items & Extensions.

## Saved startup layout

**Save current layout** records running apps, identifiable windows, their desktop UUIDs, and a backup of all custom names. It enables **Launch at login** and **Restore saved layout at login**. Save again to replace this layout. The current layout is not continuously overwritten as you work.

After login, the app waits 15 seconds for macOS session restoration and opens missing apps. Window restoration then waits up to another 30 seconds for documents to appear, matches windows by unique document/title identity, and moves ordinary windows to their saved desktop UUIDs. Every move is checked by reading its actual Space membership. Windows on inactive desktops are counted using WindowServer metadata as well as Accessibility; an empty Accessibility list does not mean those windows have closed.

On an ordinary desktop, **Save 2 Terminal windows for this desktop** saves two Terminal slots. Matching windows already on that desktop satisfy the slots. Missing Terminal windows can open as fresh login shells using local `.terminal` profiles, then move to the saved desktop. Creation is checkpointed before each attempt to prevent repeated opens after a crash. Extra existing windows are not closed. Ambiguous matches are reported rather than moved to an arbitrary task. Terminal shell commands, running jobs, tabs, and working directories are not recreated by the fresh-shell fallback.

**Restore saved layout** retries manually. Automatic restore runs once per boot/login; reopening SpaceNameBar during the same session does not rearrange your windows. Disabling launch at login disables automatic restoration too. Opening the menu is never required for startup restore.

Placement requires Accessibility and a macOS version exposing the bridged SkyLight move operation (verified locally on macOS 26.5.2). The adapter calls `SLSBridgedMoveWindowsToManagedSpaceOperation.performWithWMBridgeDelegate` dynamically and verifies the result. It does not inject into the Dock, disable SIP, require root, or request Screen Recording. References: [bridged operation declarations](https://gist.github.com/stephancasas-openai/1b31a8d76c6a103e4676ac196e06e9d8), [SIP-enabled movement reports](https://github.com/asmvik/yabai/issues/2788).

**This is not exact session reconstruction.** Other apps must reopen their own documents and tabs. Full-screen/Split View arrangements depend on macOS and the owning app; SpaceNameBar does not rebuild those arrangements. If a desktop is deleted/recreated with a different UUID, it is reported missing instead of routing to whatever desktop now occupies its old number. Missing/ambiguous windows remain listed as needing attention. No real reboot is part of the automated tests.

The app list, window identities, desktop destinations and name backup remain in `~/Library/Application Support/SpaceNameBar/startup.json`; a previous snapshot is retained. Receipts and Terminal profiles are stored in the same owner-only directory (`0700`) with owner-only files (`0600`) and atomic writes. No names, window titles, app paths or snapshots are uploaded. Files from older app-only snapshots remain readable.

Verification commands:

```sh
swift run SpaceNameCoreChecks
./scripts/check-startup.sh
~/Applications/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --check-layout-restoration
~/Applications/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --verify-layout
~/Applications/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --startup-status
```

The layout integration check creates and closes only its own two disposable windows. It exercises the actual automatic startup controller with a simulated new login, checks placement on distinct existing desktops, resumes after the app-launch phase, and verifies that a second launch in the same session does not repeat placement. `--verify-layout` is read-only; status commands print counts rather than window titles.

## Uninstall

Turn off **Restore saved layout at login** and **Launch at login**, quit the app, then move `~/Applications/SpaceNameBar.app` to the Trash. Labels stay in UserDefaults unless you explicitly remove the `com.carusiphilip.SpaceNameBar` preference domain. Startup snapshots remain in the local Application Support folder until you remove them.

Author: **Philip Carusi**. Copyright © 2026 Philip Carusi.

For troubleshooting F3 label detection, quit the app and run the installed executable with `--watch-mission-control`. This prints permission, notification-registration, event and drawing counts to the terminal; it does not print your custom names or window titles. Quit that diagnostic process and reopen the app normally afterward.
