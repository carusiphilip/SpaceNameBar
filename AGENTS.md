# Working on SpaceNameBar

Read `README.md`, `HANDOFF.md`, and `VALIDATION.md` before changing behavior. The repository is intended to be maintainable without the original development chat.

- Keep this a small native menu-bar app. Ordinary and full-screen Spaces share one continuous Desktop N sequence.
- Persist destinations by Space UUID; never substitute a desktop number when a UUID disappears.
- Preserve the F3 recovery mechanisms and the WindowServer inventory fallback for inactive desktops. Both prevent regressions reproduced during development.
- Use disposable windows/apps for tests. Do not resave the user's startup layout merely to test a build: saving replaces their intended layout. Do not close real work windows or reboot the Mac as part of routine verification.
- User data belongs in UserDefaults and the private Application Support directory described in the README. Never commit snapshots, Terminal profiles, real desktop names, window titles, personal app paths, or diagnostic output containing them.
- Keep normal system security enabled. Do not add Dock injection or require disabling SIP.
- The repository owner and author is Philip Carusi. Preserve existing author metadata and do not add co-author trailers.
- For code changes, run the relevant checks listed in `HANDOFF.md`. Documentation-only changes need link/content checks, not app relaunches or window tests.
- Update documentation when behavior or limitations change. Distinguish verified window placement from exact session reconstruction.
