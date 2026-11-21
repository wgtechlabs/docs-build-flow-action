# Contributing to Docs Build Flow Action

Thank you for your interest in contributing to this project. We welcome contributions from the community.

## Commit message convention

This repository follows the **Clean Commit** convention.

Reference: https://github.com/wgtechlabs/clean-commit

### Format

```text
<emoji> <type>: <description>
<emoji> <type> (<scope>): <description>
```

### The 9 types

| Emoji | Type | What it covers |
|:-----:|------|----------------|
| 📦 | `new` | Add new features, files, or functions |
| 🔧 | `update` | Change code, improve, fix |
| 🗑️ | `remove` | Delete code, files, or features |
| 🔒 | `security` | Fix security problems |
| ⚙️ | `setup` | Change configs, CI/CD, build systems |
| ☕ | `chore` | Maintenance, update dependencies |
| 🧪 | `test` | Add or fix tests |
| 📖 | `docs` | Change documentation |
| 🚀 | `release` | Release versions |

### Rules

- Use the exact emoji and a lowercase type.
- Use present tense ("add", not "added").
- Start the description with a lowercase letter.
- No period at the end.
- One space after the colon.
- Keep the subject under 72 characters.

### Examples

- `📦 new: add user authentication`
- `🔧 update (api): improve error messages`
- `🗑️ remove: old login method`
- `🔒 security: fix xss issue`
- `⚙️ setup (ci): add github actions`
- `☕ chore (deps): update npm packages`
- `🧪 test: add auth unit tests`
- `📖 docs: update readme`
- `🚀 release: version 1.0.0`

## Branches and pull requests

This repository follows **Clean Flow**.

Reference: https://github.com/wgtechlabs/clean-flow

1. Fork the repository and clone it.
2. Create a branch from `dev`:
   ```bash
   git checkout dev
   git checkout -b feature/your-feature-name
   ```
3. Commit with Clean Commit.
4. Open the pull request against `dev`.

Send feature work to `dev`. Do not open feature pull requests against `main`.

Do not add or edit `CHANGELOG.md`. The release workflow generates it.

## Pull request guidelines

- Describe the problem and the change.
- Link the issue when there is one.
- Update the docs when the behavior changes.
- Keep the pull request to one feature or one fix.
- Run `bash run-tests.sh` before you submit.

## Code style

- Follow the existing bash style.
- Use meaningful names.
- Comment a step only when the reason is not obvious.
- Keep each script focused on one part of the build.

## Questions

Open an issue for questions.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
