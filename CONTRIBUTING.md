# Contributing

## Development setup

1. Install Xcode Command Line Tools or Xcode.
2. Clone the repository.
3. Run `./scripts/build_app.sh`.
4. Launch the generated `.app` from the repository directory.

## Pull requests

- Keep changes focused on one problem.
- Explain the user-facing behavior and any matching-rule changes.
- Include a test case or a clear manual verification description for metadata rules.
- Do not include personal Apple Music library exports, account information, or credentials.
- Preserve the rule that lyrics do not determine title language.

## Bug reports

Use the GitHub issue template and include:

- macOS version
- App version
- Steps to reproduce
- Expected behavior
- Sanitized debug output

Remove all personal file paths and private metadata before posting logs.
