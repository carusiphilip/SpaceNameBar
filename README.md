# SpaceNameBar

A small native macOS menu bar app that gives each desktop a name: **💬 Agent Runners**, **Documentation**, **Builds**, or whatever helps you find your place.

## Use

1. Open `SpaceNameBar.app` from your Applications folder.
2. Click the desktop name in the menu bar.
3. Enter a name and press **Return** (or click **Save Name**).
4. Switch desktops normally. The menu bar updates to that desktop's saved name.

**Reset Name** restores the default label. Saving an empty name does the same. Emoji are supported; names are limited to 80 characters. Short names fit best on crowded menu bars. Enable **Launch at login** in the popover if desired. There is no Dock icon or main window; quit from the popover.

This labels your menu bar; it does not change Apple's desktop titles in Mission Control.

## Build and install

Requires macOS 13 or later and Swift 6 or later (Xcode or Apple's Command Line Tools). No third-party dependencies.

```sh
./scripts/install.sh
```

This builds a release app, ad-hoc signs it, copies it to `~/Applications/SpaceNameBar.app`, and opens it. For updates, quit the existing app first. Build only with `./scripts/build.sh`. The bundle is in `dist/SpaceNameBar.app` and is built for the current Mac's architecture.

The local build does not need a paid Apple developer account. It is not Developer ID signed or notarized for distribution to other Macs.

## How detection works

SwiftUI `MenuBarExtra` with `.window` style provides a dropdown that supports a real text field. `LSUIElement` keeps the app out of the Dock. The app listens through `NSWorkspace.shared.notificationCenter` for `activeSpaceDidChangeNotification`. It also refreshes on wake, session activation, display changes, app activation (for display focus), and menu opening. Each system event has one cancellable 350 ms follow-up to handle transition timing. There is no periodic polling, input monitoring, background network traffic, or subprocess in the detection path.

Apple's public notification contains no Space identifier. A small isolated adapter dynamically resolves three **undocumented, read-only SkyLight functions**:

- `CGSMainConnectionID`
- `CGSCopyManagedDisplaySpaces`
- `CGSCopyActiveMenuBarDisplayIdentifier`

It reads the current desktop and its UUID. No injection, workspace manipulation, Accessibility permission, Screen Recording permission, root privileges, or SIP changes are used. Missing functions or unrecognizable data produce an unavailable message and disable naming instead of assigning a label to an arbitrary desktop. Private APIs can change in a macOS update; this is a personal utility, not an App Store submission.

References: [Apple's notification documentation](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification), [CGS display declarations](https://github.com/NUIKit/CGSInternal/blob/master/CGSDisplays.h).

## Persistence and displays

Labels live locally in `UserDefaults`, domain `com.carusiphilip.SpaceNameBar`, key `spaceLabels.v1`. The map uses Space UUIDs, **not numeric IDs or desktop positions**. Numeric IDs can change across sessions. Reordering an existing desktop preserves its label; labels remain stored across app exits, logout, and restart. If macOS deletes/recreates a Space or assigns it a new UUID, it is a new desktop and needs a new name. Full-screen Spaces can also be named, but macOS may recreate them when apps reopen. Old mappings are retained so a temporarily absent Space can recover its name.

With multiple displays, the shared menu bar title follows the active menu bar display; opening the editor targets the display under the pointer. macOS mirrors a single `MenuBarExtra` across screens, so this version does **not** render different simultaneous titles on each monitor. Moving only the pointer, without changing Spaces, activating an app, or opening the menu, does not trigger a refresh. With unified Spaces, a single visible desktop is supported even when macOS identifies the display as `Main`.

The editor rechecks the visible Space before saving. If it changed mid-edit, the old name is not written to a different Space.

## Verification

```sh
swift run SpaceNameCoreChecks
./scripts/build.sh
./dist/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --diagnose
```

The dependency-free checks run with Command Line Tools alone. They cover UUID identity across reordering/new session IDs, full-screen numbering, multiple displays, unified displays, malformed data, current-Space resolution, independent persisted labels/reset, and Unicode limits. The diagnostic command prints Space metadata only and exits; it does not save labels.

Manual checks for a macOS update:

1. Name two desktops differently and switch between them using your usual gestures or shortcuts.
2. Quit/reopen the app and confirm both labels remain.
3. Reorder a named desktop in Mission Control and confirm its label follows it.
4. Check full-screen Spaces, sleep/wake, and any external displays you use.
5. Enable launch at login, log out/in, and confirm startup. If macOS requests approval, allow SpaceNameBar in System Settings → General → Login Items & Extensions.

## Uninstall

Turn off **Launch at login**, quit the app, then move `~/Applications/SpaceNameBar.app` to the Trash. Labels stay in UserDefaults unless you explicitly remove the `com.carusiphilip.SpaceNameBar` preference domain.
