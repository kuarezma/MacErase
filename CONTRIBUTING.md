# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Before you open a PR

```bash
swift build -c release
swift test
python3 Scripts/check_l10n.py   # must report 0 errors
```

- **Deleting files is the sensitive part.** Any change to matching (`AppScanner`), cleaning roots (`CleanKind`), Large Files filtering or removal code (`FileUtil`) needs a test. Tests must work only inside a temporary folder and never touch real user files.
- **User-facing text** is written in Turkish in the source (`String(localized:)`, `Text("…")`). Add each new key to both `Resources/tr.lproj` (key = value) and `Resources/en.lproj`.
- Keep the app dependency-free and light. Don't add telemetry or network access.
- Match the surrounding style. `.swiftlint.yml` lists the enforced rules.

## Reporting bugs

Use the issue templates. For anything that could delete the wrong data, follow [SECURITY.md](SECURITY.md) instead.
