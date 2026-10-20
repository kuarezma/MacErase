# Changelog

All notable changes to MacErase are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.0.1] - 2026-10-20

### Safety
- Apps that ship with macOS (including `/Applications/Safari.app`, which links into a system cryptex) are no longer listed or accepted by drag and drop, so their data folders can't be trashed by mistake.
- Removal with administrator rights now accepts only an `.app` bundle in `/Applications` or an item inside a `/Library` subfolder. Top-level folders, `.`/`..` segments and other locations are refused.
- Large Files skips Git working trees (including worktrees and submodules) and dependency or build folders such as `node_modules`, `Pods`, `venv` and `DerivedData`, so it no longer suggests individual project files.
- Startup Items refuses to unload or remove anything that isn't a user-owned `.plist`.

### Fixes
- Smart Clean: a scan that was replaced by a new one could append stale categories with partial sizes and end the new scan early.
- Uninstaller: a cancelled app scan no longer publishes partial sizes. You can't switch apps or press Undo while an uninstall is running. The leftover spinner no longer gets stuck after you clear the selection.
- Uninstaller: errors such as "This is not an application" now show as a warning instead of a "Done" screen.
- Settings showed a hard-coded version (1.0). It now reads the bundle version.
- In English, the Startup Items button now says "Remove" instead of "Uninstall". On system items it's grey (disabled) instead of red.
- Startup Items reloads each time you open the section, so it reflects uninstalls made elsewhere.

### Improvements
- Smart Clean shows at most 300 rows per category (the rest stay selected), so a large Trash no longer slows the window.
- The system widgets publish only values that changed, which avoids unnecessary redraws.
- VoiceOver labels for the widget pills, the refresh and widget buttons, the sort picker and the category switches.
- Apps now fall back to English for languages other than English and Turkish. The app bundle includes copyright information.
- `Scripts/check_l10n.py` also checks ASCII-only UI strings (for example "Tara") and reports unused keys. CI runs it.
- New tests cover Smart Clean candidates, Large Files filtering, admin-removal path checks and system-app rejection.

## [1.0.0] - 2026-10-20

- First public release: app uninstaller with leftover finder, Smart Clean, Large Files, Startup Items, live widgets and an optional menu bar item. English and Turkish.
