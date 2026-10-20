# Security Policy

MacErase deletes files, so bugs that could remove the wrong data are treated as security issues.

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Please **do not** open a public issue. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository.

Include the macOS version, the MacErase version and the steps to reproduce. For a matching bug, include the paths involved (you can redact your user name). You should get a reply within a few days.

Examples that count:

- MacErase offers, selects or removes something that doesn't belong to the chosen app or category.
- A path escapes its intended folder (through symlinks, `..` or similar).
- The administrator-removal path can be made to delete something outside `/Applications` or `/Library`.
