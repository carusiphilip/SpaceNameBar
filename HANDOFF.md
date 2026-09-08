# Maintenance handoff

## Current release

Version 1.3.0, build 5. The installed app is `~/Applications/SpaceNameBar.app`; the source repository is `SpaceNameBar`. `main` is the default branch of the public GitHub repository. There are no third-party package dependencies.

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

**F3:** Dock opening/exit notifications alone proved unreliable. The current service starts eagerly, recovers an already-open Mission Control, observes relevant shortcuts, checks for missed openings once per second, and recreates panels on every opening. Geometry refresh runs every 200 ms only while Mission Control is open. The user confirmed the latest recovery kept names visible. This is still an undocumented Dock integration, not a guarantee across future macOS releases.

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

The first command checks pure logic and persistence. The second launches and terminates only a disposable test app and exercises automatic startup with simulated sessions. The third creates and verifies an ad-hoc signed release bundle in `dist/`.

With the installed app's existing Accessibility permission and at least two ordinary desktops, this additional check creates and closes only two disposable windows:

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
