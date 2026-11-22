---
title: Requirements
navTitle: Requirements
order: 1
---
# Requirements

Use `wgtechlabs/docs-build-flow-action@v0`.

The latest release is [v0.1.0](https://github.com/wgtechlabs/docs-build-flow-action/releases/tag/v0.1.0). The `v0` tag points at the same commit as `v0.1.0`.

The release workflow in `.github/workflows/release.yml` sets `update-major-tag: true` on `wgtechlabs/release-build-flow-action@v1`.

## Runner

The action reads `uname -s` in `scripts/prepare-site.sh`, `scripts/build-docs.sh`, and `scripts/package-site.sh`.

If the value is not `Linux`, the action stops with this text:

```text
This action requires a Linux runner.
```

`scripts/build-docs.sh` also requires `docker` on `PATH`. If the command is missing, the action stops with this text:

```text
Required command not found: docker
```

The example workflows set `runs-on: ubuntu-latest`. The action checks `uname -s`.

The image is `wgtechlabs/mdd:` plus the `mdd-version` input. The default image is `wgtechlabs/mdd:0.3.0`.

## Checkout

Run `actions/checkout` before this action. The action reads the MDD folder from `GITHUB_WORKSPACE`.

If `GITHUB_WORKSPACE` is unset, `scripts/build-docs.sh` stops with this text:

```text
Set GITHUB_WORKSPACE. Checkout the repository before this action.
```

If `source-dir` is not a directory inside that workspace, the action stops with both of these lines:

```text
source-dir mdd does not exist in the workspace.
An MDD folder needs contents/index.md. Checkout the repository before this action.
```

The first line includes the `source-dir` value you set. The second line is a hint. This check tests that the path is a directory. The image checks the homepage file.

## MDD folder

The default `source-dir` is `mdd`. The folder must contain the MDD homepage.

`scripts/mdd-build.mjs` calls `resolveContentFolder` in the `wgtechlabs/mdd` image. That function accepts the folder when the homepage file exists.

The homepage path is `contents/index.md`. If `config.json` sets `paths.contents` to a nonempty string, the homepage is `index.md` inside that path instead. The path is resolved from the MDD folder and must stay inside the project.

`config.json` is optional. If the file is missing, or if `paths.contents` is missing or empty, the homepage stays `contents/index.md`.

If `config.json` is not valid JSON, the folder check still looks for `contents/index.md`. When that file exists, the build reports this diagnostic and stops:

```text
config.json must contain valid JSON.
```

If the homepage check fails, the build exits with this error:

```text
MDD_DOCS_DIR=mdd is not an MDD folder: mdd/contents/index.md is missing. An MDD folder needs contents/index.md (or the index.md of paths.contents in its config.json). config.json is optional.
```

The reason changes with the failure:

| Condition | Reason in the error |
| --- | --- |
| The homepage file is missing | `mdd/contents/index.md is missing` |
| A segment of `source-dir` is a symlink | `mdd/ is not a real directory` |
| `paths.contents` points outside the project | `mdd/ points paths.contents outside the project` |

A symlink to a directory passes the directory test in `scripts/build-docs.sh`. The image then rejects it. The `mdd/` prefix in each reason is the `source-dir` value.

## Permissions

The example workflows set these permissions:

```yaml
permissions:
  contents: read
  pages: read
  actions: write
  id-token: write
```

| Permission | Where it is used |
| --- | --- |
| `contents: read` | The checkout step in the examples. |
| `pages: read` | The Pages request. HTTP 401 and HTTP 403 stop with `Cannot read GitHub Pages (HTTP 401). Grant this job pages: read.` The status in the text is `401` or `403`. |
| `actions: write` | The example grant on the job that uploads `github-pages`. List and download errors ask for `actions: read`. The statuses are on [How it works](../usage/index.md#errors). |
| `id-token: write` | The example grant on the job that also runs `actions/deploy-pages`. The scripts read `github-token` only. |

`github-token` defaults to `${{ github.token }}`. The scripts send it as `Authorization: Bearer` with `Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28`.

If the token is empty, resolve stops with this text:

```text
github-token is required to read GitHub Pages.
```

In workflow mode, an empty token stops later with this text:

```text
github-token is required to download the Pages artifact.
```

## Commands

If a required command is missing, the text is `Required command not found:` followed by the command name.

| Command | Script that requires it |
| --- | --- |
| `jq` | `scripts/resolve-pages.sh`. Also `scripts/prepare-site.sh` when it lists artifacts. |
| `curl` | `scripts/resolve-pages.sh` when it calls the API. `scripts/prepare-site.sh` when it downloads an artifact. |
| `unzip` | `scripts/prepare-site.sh` when it opens the artifact zip. |
| `tar` | `scripts/prepare-site.sh` when it reads `artifact.tar`. `scripts/package-site.sh` when it writes the new archive. |
| `docker` | `scripts/build-docs.sh`. |

## Pages source

Set the Pages source before you rely on workflow mode.

| `build_type` on HTTP 200 | Result |
| --- | --- |
| `workflow` | Workflow mode. |
| `legacy` | The action stops. |
| Any other value, including a missing value | The action stops. |

A legacy site prints these three lines. `owner/repo` is `GITHUB_REPOSITORY`.

```text
GitHub Pages for owner/repo uses the legacy build.
Set the Pages source to GitHub Actions: https://github.com/owner/repo/settings/pages
Then run this action after actions/upload-pages-artifact and before actions/deploy-pages.
```

A missing `build_type` prints `Unsupported GitHub Pages build type: unknown.` Any other value is printed in that same sentence.

HTTP 404 is standalone mode. It is not an error. [Publish the docs as the whole site](./standalone.md) when that is the result you want.

HTTP 200 with `build_type` `workflow` is [an existing site](./existing-site.md).

The full error list is on [How it works](../usage/index.md). Input rules are on [Inputs and outputs](../usage/inputs-outputs.md).
