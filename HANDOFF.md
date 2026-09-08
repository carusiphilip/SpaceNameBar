# Maintenance handoff

## Current release

Version 1.3.1, build 7. The installed app is `~/Applications/SpaceNameBar.app`; the source repository is `SpaceNameBar`. `main` is the default branch of the public GitHub repository. There are no third-party package dependencies.

The app provides custom desktop names in the menu bar, F3 desktop/window overlays, launch at login, and saved window destinations. The README documents installation and user-facing behavior. `VALIDATION.md` records checks and their limits by release; older entries describe older behavior.

## Source map

| Area | Files |
| --- | --- |
| Menu and eager startup entry point | `Sources/SpaceNameBar/SpaceNameBarApp.swift` |
| Current desktop, naming, login toggle | `Sources/SpaceNameBar/SpaceModel.swift` |
| Live Space metadata and numeric ID resolution | `Sources/SpaceNameBar/SpaceDetector.swift` |
| F3 notifications, recovery and overlay drawing | `Sources/SpaceNameBar/MissionControlLabels.swift` |
| Capture, login/session gating and app launch | `Sources/SpaceNameBar/StartupController.swift` |
| AX/WindowServer window inventory and verified movement | `Sources/SpaceNameBar/WindowLayout.swift` |
| Window assignment and placement orchestration | `Sources/SpaceNameBar/LayoutRestorer.swift` |
| Fresh Terminal shells from local profiles | `Sources/SpaceNameBar/TerminalWindows.swift` |
| Small dynamic Objective-C SkyLight adapter | `Sources/WindowSpaceBridge/` |
| Persisted models, matching and launch receipts | `Sources/SpaceNameCore/` |
| Dependency-free core checks | `Tests/SpaceNameCoreTests/` |
| Native integration checks | `Sources/SpaceNameBar/StartupIntegrationChecks.swift`, `Sources/SpaceNameBar/LayoutIntegrationChecks.swift` |

## State that survives clearing a chat

The application never reads this chat. Labels are in UserDefaults domain `com.carusiphilip.SpaceNameBar`, key `spaceLabels.v1`. Login restore settings are also in that domain; macOS manages the login-item registration.

Private startup data is in `~/Library/Application Support/SpaceNameBar/`:

- `startup.json`: the desired saved layout, including labels and Terminal slots.
- `startup.previous.json`: the previous snapshot, retained when saving again.
- `startup-receipt.json`: attempts, failures and completion for the boot/login session.
- `terminal-<UUID>.terminal`: generated fresh-shell profiles.

Use the installed executable's `--startup-status` to inspect current counts/settings and `--verify-layout` to check saved destinations without moving windows. Do not assume that a fresh development checkout has the installed app's preferences or Accessibility permission. Preserve the bundle identifier and installation path during updates.

## Regression details to retain

**F3:** Dock opening/exit notifications alone proved unreliable. The current service starts eagerly, recovers an already-open Mission Control, observes relevant shortcuts, checks for missed openings once per second, and recreates panels on every opening. Geometry refresh runs every 200 ms only while Mission Control is open. Earlier user confirmation was temporary: the failure recurred. Version 1.3.1 identified a separate permission/signing failure; do not infer lasting success from a Terminal diagnostic. This is still an undocumented Dock integration, not a guarantee across future macOS releases.

**Inactive desktops:** AXWindows can omit windows on inactive ordinary and full-screen Spaces. Treating that as a closed window created extra Terminals during early live tests. Keep the WindowServer metadata fallback, and do not test missing-window creation using only the Accessibility count.

**Matching:** Unique titles/documents allow moving a window. A window already on its saved desktop can satisfy an app's slot even if its title changed or is unreadable. Consequently, a successful destination check verifies desktop assignments/counts, not exact document contents, terminal sessions or tab state.

**Terminal counts:** Creation is limited by the total saved-versus-live Terminal deficit and checkpointed before each open. Existing extra windows are never closed. If enough Terminals exist elsewhere but cannot be matched safely, a requested desktop may remain unresolved rather than receive a duplicate or an unrelated window. Earlier tests left extra windows open; inspect current state instead of assuming they still exist. macOS may independently reopen any extras the user leaves open.

**Restore completion:** App launching and placement have separate completion fields. A receipt with completed app launches must not suppress unfinished placement. Automatic restore is once per boot/login; manual restore resets the receipt. Saving a layout marks the current session complete so a rebuild/relaunch does not rearrange current work.

**Limits:** Missing Space UUIDs are not remapped by desktop number. Full-screen/Split View recreation depends on macOS and the owning app. Fresh Terminal shells do not replay jobs, commands, working directories or tabs. A real reboot/logout has not been tested; do not describe the simulated-login checks as a reboot guarantee.

## Checks and updates

Run SwiftPM commands sequentially; they share `.build`.

```sh
swift run SpaceNameCoreChecks
./scripts/check-startup.sh
./scripts/build.sh
```

The first command checks pure logic and persistence. The second launches and terminates only a disposable test app and exercises automatic startup with simulated sessions. The third creates and verifies a locally certificate-signed release bundle in `dist/`.

With the test launcher's Accessibility permission and at least two ordinary desktops, this additional check creates and closes only two disposable windows:

```sh
~/Applications/SpaceNameBar.app/Contents/MacOS/SpaceNameBar --check-layout-restoration
```

It tests the production automatic controller, actual movement to distinct desktops, recovery after app-launch completion and same-login suppression. It does not reboot or close the user's apps.

For installation, quit the running SpaceNameBar, run `./scripts/install.sh`, and leave the app running normally afterward. Check F3 after repeated openings and an app restart with Mission Control already open. Updating the bundle briefly removes the overlay until the new process starts.

`--watch-mission-control` is a diagnostic mode: quit the normal instance first, run the installed executable with this flag, then quit that process and reopen the app normally. It prints event/drawing counts and does not start automatic layout restoration.

The following are **mutating** maintenance commands, not routine verification:

| Command | Effect |
| --- | --- |
| `--save-startup` | Replaces the saved layout with current apps/windows and enables login restore. |
| `--configure-terminals <Space-UUID> <count>` | Replaces Terminal slots for one ordinary desktop in the saved layout. |
| `--restore-layout` | Resets the current receipt and restores apps/windows now. |

Before publishing, review staged paths for user data, run `git diff --check`, push to `main`, and verify both a clean working tree and matching local/remote commits. Build artifacts and private runtime data are not repository deliverables.

## Recurring F3 failure: signing and misleading diagnostics

The normally launched 1.3.0 process was denied Accessibility (confirmed in TCC request results), although a direct Terminal launch of the same executable returned trusted. The latter inherited Terminal’s responsible-process attribution. The saved permission’s code hash did not match the installed build. Earlier `--watch-mission-control` success therefore did not establish permission in normal operation.

`build.sh` now uses `sign.py` and an app-specific local certificate pinned by fingerprint in the designated requirement. Signing material is private under Application Support, never in the checkout. Do not replace it, use an identifier-only requirement, modify the TCC database, or launch through Terminal as a permission workaround. Python 3 and system OpenSSL/security/codesign tools are required. The keychain search list is restored after signing; run builds sequentially. Run `./scripts/check-signing.sh` after building to verify identity continuity across changed contents.

On upgrade from the old hash identity, the user must renew Accessibility for the installed app once. Check permission in the normally launched process via the MissionControl unified-log category documented in README. The menu shows a warning for missing permission and the watchdog continues checking for a renewed grant. Normal diagnostics contain counts only. A Terminal CLI prints an explicit warning about inherited permission.
