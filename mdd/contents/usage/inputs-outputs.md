---
title: Inputs and outputs
navTitle: Inputs and outputs
order: 5
---
# Inputs and outputs

Every input is optional. When you omit an input, `action.yml` passes its default.

`docs-path`, `source-dir`, `mdd-version`, and `base-path` are trimmed. `github-token` is not trimmed.

The scripts also fall back to `docs`, `mdd`, and `0.3.0` when the matching variable is unset. An empty string stays empty.

| Input | Empty value |
| --- | --- |
| `github-token` | An empty token stops with `github-token is required to read GitHub Pages.` Spaces are kept. |
| `base-path` | The automatic prefix below. A value that is only spaces takes the same path. |
| `docs-path` | `docs-path must be a relative path such as mdd or docs.` |
| `source-dir` | `source-dir must be a relative path such as mdd or docs.` |
| `mdd-version` | `mdd-version must be a Docker tag such as 0.3.0.` |

## Inputs

| Input | Default | Role |
| --- | --- | --- |
| `github-token` | `${{ github.token }}` | Token for the Pages request and for the artifact list and download. |
| `base-path` | Empty | Public prefix passed to MDD. Empty selects the prefix in [Base path](#base-path). |
| `docs-path` | `docs` | Directory that receives the docs in workflow mode. |
| `source-dir` | `mdd` | MDD folder inside the repository. |
| `mdd-version` | `0.3.0` | Tag of the `wgtechlabs/mdd` image. |

`scripts/resolve-pages.sh` also writes step outputs named `source-dir` and `mdd-version`. `action.yml` does not expose those two names. The action outputs are only the four names in [Outputs](#outputs).

## Path inputs

`docs-path` and `source-dir` use one rule.

The value is one or more segments joined by `/`. Each segment contains letters, digits, `.`, `_`, or `-`. The value has no leading slash and no trailing slash.

These values pass: `mdd`, `docs`, `docs/api`, `site.v2`.

| Value | Error text |
| --- | --- |
| `../docs`, `/docs`, `docs/`, or `my docs` | `docs-path must be a relative path such as mdd or docs.` |
| `.mdd`, `.git`, `.github`, or `mdd/.github` | `source-dir cannot contain a hidden path segment.` |

The label in the error is `docs-path` or `source-dir`, matching the input that failed. A segment that starts with `.` is a hidden segment. That rejects `.git` and `.github`.

Whitespace around a valid value is removed first. ` docs ` is `docs`.

In standalone mode the input is still validated. The output `docs-path` is empty, and the files are copied to the site root. See [Standalone site](../get-started/standalone.md).

In workflow mode the files are copied to this path under the site root. The output `docs-path` is the same path.

## mdd-version

The tag is 1 to 128 characters. It starts with a letter, a digit, or `_`. The remaining characters are letters, digits, `_`, `.`, or `-`.

The image is always `wgtechlabs/mdd:` plus that tag. A slash, a colon, or a second path segment fails the tag check. `0.3.0/evil` stops with this text:

```text
mdd-version must be a Docker tag such as 0.3.0.
```

The default tag builds `wgtechlabs/mdd:0.3.0`.

## Base path

`base-path` is trimmed. A value that is empty after trimming selects the automatic prefix. A value that contains only spaces does the same.

### Automatic prefix

1. Start with `/`.
2. On HTTP 200, read `cname`. Null, missing, and `""` are unset. HTTP 404 does not read `cname`.
3. Compare the repository name with `owner.github.io`. The comparison is lowercase. `owner` is the text before the slash in `GITHUB_REPOSITORY`.
4. If `cname` is unset and the names differ, use `/`, the repository name as written, and `/`.
5. If `cname` is nonempty, or the names match, keep `/`.
6. In workflow mode, append the docs path and `/`.
7. In standalone mode, leave the docs path off the prefix.

| HTTP | `build_type` | `cname` | Repository | `docs-path` | `base-path` input | Mode | `base-path` output | `docs-path` output |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 404 | not read | not read | `wgtechlabs/docs-build-flow-action` | `docs` | empty | `standalone` | `/docs-build-flow-action/` | empty |
| 404 | not read | not read | `WGTechLabs/Docs-Build-Flow-Action` | `docs` | empty | `standalone` | `/Docs-Build-Flow-Action/` | empty |
| 404 | not read | not read | `wgtechlabs/wgtechlabs.github.io` | `docs` | empty | `standalone` | `/` | empty |
| 404 | not read | not read | `Acme/ACME.github.io` | `docs` | empty | `standalone` | `/` | empty |
| 404 | not read | not read | `acme/docs.github.io` | `docs` | empty | `standalone` | `/docs.github.io/` | empty |
| 404 | not read | not read | `wgtechlabs/docs-build-flow-action` | `guides` | empty | `standalone` | `/docs-build-flow-action/` | empty |
| 200 | `workflow` | null | `wgtechlabs/docs-build-flow-action` | `docs` | empty | `workflow` | `/docs-build-flow-action/docs/` | `docs` |
| 200 | `workflow` | `docs.example.com` | `wgtechlabs/docs-build-flow-action` | `docs` | empty | `workflow` | `/docs/` | `docs` |
| 200 | `workflow` | `""` | `wgtechlabs/docs-build-flow-action` | `docs` | empty | `workflow` | `/docs-build-flow-action/docs/` | `docs` |
| 200 | `workflow` | null | `acme/acme.github.io` | `guides` | empty | `workflow` | `/guides/` | `guides` |
| 200 | `workflow` | null | `wgtechlabs/docs-build-flow-action` | `docs/api` | empty | `workflow` | `/docs-build-flow-action/docs/api/` | `docs/api` |

### Set a prefix

A nonempty value replaces the automatic prefix.

1. Add a leading `/` when the value has none.
2. Add a trailing `/` when the value has none.
3. Accept `/`.
4. Accept any other value made of one or more `/segment/` parts.
5. Each segment uses letters, digits, `.`, `_`, or `-`.
6. Reject a segment that is `.` or `..`, and reject a segment that starts with `.`.

The slashes are added before the check.

| Input | Result |
| --- | --- |
| `guide` | `/guide/` |
| ` guide ` | `/guide/` |
| `docs` | `/docs/` |
| `/docs` | `/docs/` |
| `docs/` | `/docs/` |
| `/repo/docs/` | `/repo/docs/` |
| `/` | `/` |

These values stop the action:

| Input | Error text |
| --- | --- |
| `my docs`, `//docs`, `docs//api`, or `docs?` | `base-path must look like /, /docs/, or /repo/docs/.` |
| `/.hidden`, `/../docs`, or `/./` | `base-path cannot contain a hidden or parent segment.` |

In workflow mode, a prefix that does not end with `/` plus the docs path plus `/` produces a warning. The action still uses the prefix and still copies files to the docs path. For docs path `docs` and base path `/guide/`, the warning is:

```text
base-path /guide/ does not end with /docs/. Page links may not match the published directory.
```

The resolved value is the `base-path` output and the `MDD_BASE_PATH` value passed to MDD.

## Outputs

These outputs are set when the action succeeds.

| Output | Value |
| --- | --- |
| `mode` | `standalone` or `workflow`. |
| `base-path` | The public prefix passed to MDD. It starts and ends with `/`. |
| `docs-path` | The directory that received the docs. An empty string in standalone mode. |
| `artifact-name` | `github-pages`. |

`mode` is `standalone` when the Pages request returns HTTP 404. It is also `standalone` when the request returns HTTP 200, `build_type` is `workflow`, and this run has no `github-pages` artifact. It is `workflow` when that artifact exists. A legacy or unsupported site stops before outputs are written.

## Read an output

Use the step id in a later step of the same job:

```yaml
- name: Build docs
  id: docs
  uses: wgtechlabs/docs-build-flow-action@v0

- name: Show the result
  run: |
    echo "${{ steps.docs.outputs.mode }}"
    echo "${{ steps.docs.outputs.base-path }}"
    echo "${{ steps.docs.outputs.docs-path }}"
    echo "${{ steps.docs.outputs.artifact-name }}"
```

Runtime errors are listed on [How it works](./index.md#errors).
