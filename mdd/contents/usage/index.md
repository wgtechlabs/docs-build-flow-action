---
title: How it works
navTitle: How it works
order: 4
---
# How it works

`action.yml` runs five steps in order. The first four call shell scripts. The last step uploads the archive.

| Step | Implementation |
| --- | --- |
| Resolve Pages mode | `scripts/resolve-pages.sh` |
| Prepare site directory | `scripts/prepare-site.sh` |
| Build documentation | `scripts/build-docs.sh` and `scripts/mdd-build.mjs` |
| Package Pages artifact | `scripts/package-site.sh` |
| Upload Pages artifact | `actions/upload-artifact@v7.0.2` |

Working files are stored in `RUNNER_TEMP/docs-build-flow`. If `RUNNER_TEMP` is unset, the directory is `/tmp/docs-build-flow`.

## Resolve the mode

`scripts/resolve-pages.sh` requires `jq` and `GITHUB_REPOSITORY` in `owner/repo` form.

It trims `docs-path`, `source-dir`, and `mdd-version`, then validates them. Those checks run before the Pages request. The rules are on [Inputs and outputs](./inputs-outputs.md).

It calls this API unless the token check fails first:

```text
GET /repos/{owner}/{repo}/pages
```

The host is `GITHUB_API_URL` when that variable is set. Otherwise the host is `https://api.github.com`.

| HTTP status | Result |
| --- | --- |
| 404 | Mode `standalone`. The body is not parsed. |
| 200 | The body must be JSON. `build_type` must be `workflow` or `legacy`. |
| 401 | Stop. `Cannot read GitHub Pages (HTTP 401). Grant this job pages: read.` |
| 403 | Stop. `Cannot read GitHub Pages (HTTP 403). Grant this job pages: read.` |
| Any other status | Stop. `GitHub Pages request failed with HTTP 500.` The number is the status GitHub returned. |

On HTTP 200, invalid JSON stops with `GitHub Pages returned invalid JSON.`

`build_type` `workflow` sets mode `workflow`. `build_type` `legacy` prints the three lines on [Requirements](../get-started/index.md#pages-source). Any other value, including a missing value, stops with `Unsupported GitHub Pages build type: unknown.` A present value replaces `unknown`.

The script then computes the base path and writes step outputs. The action outputs are `mode`, `base-path`, `docs-path`, and `artifact-name`.

On success the log text matches this shape:

```text
Pages mode is workflow. Base path is /docs-build-flow-action/docs/.
```

## Prepare the site

`scripts/prepare-site.sh` requires Linux. The mode must be `standalone` or `workflow`. Any other value stops with `Unknown Pages mode:` and the value.

It creates `site` under the work directory. An existing `site` directory is removed first.

In standalone mode the directory stays empty. The log text is `No Pages site found. The docs will be the whole site.`

In workflow mode the script lists artifacts for this run:

```text
GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts?per_page=100&page={page}
```

`run_id` is `GITHUB_RUN_ID`. Each page must return HTTP 200 and valid JSON. Any other status stops with `Cannot list workflow artifacts (HTTP 403). Grant this job actions: read.` Invalid JSON stops with `The artifact list was not valid JSON.`

The script keeps objects whose `name` is `github-pages` and whose `expired` is false. It chooses the greatest `created_at`. It stops after 20 pages.

It downloads the chosen artifact:

```text
GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip
```

| Download status | Result |
| --- | --- |
| 200 | The response body is the zip. |
| 301, 302, 303, 307, or 308 | The script reads one `Location` header. That URL must start with `https://`. It then downloads the URL with `curl -fsSL`, which follows later redirects. |
| 401 | Stop. `Cannot download the Pages artifact (HTTP 401). Grant this job actions: read.` |
| 403 | Stop. `Cannot download the Pages artifact (HTTP 403). Grant this job actions: read.` |
| Any other status | Stop. `Artifact download failed with HTTP 500.` The number is the status GitHub returned. |

A redirect with no location stops with `Artifact download redirected without a location.` A location that does not start with `https://` stops with `Artifact download redirected to a non-HTTPS URL.`

The zip must contain `artifact.tar` at its top. The tar is extracted into the site directory after the unsafe-path check on [the existing-site page](../get-started/existing-site.md#artifact-rules).

On success the log text is `Extracted the current Pages artifact.`

## Build the docs

`scripts/build-docs.sh` requires Linux, `docker`, a site directory, and a `source-dir` directory in `GITHUB_WORKSPACE`.

It validates `source-dir`, `base-path`, and `mdd-version` again. The image reference is `wgtechlabs/mdd:` plus the tag. The default is `wgtechlabs/mdd:0.3.0`.

The image entrypoint is `node /app/dist/container-server.js`. That process builds the mounted project and then starts the MDD server. This step replaces the entrypoint and runs `node /opt/mdd-build.mjs`, which calls `build()` and exits.

The container runs as the current user and group. `HOME` is `/tmp`. The workspace is mounted read-only at `/workspace`. The script sets these variables:

| Variable | Value |
| --- | --- |
| `MDD_PROJECT_DIR` | `/workspace` |
| `MDD_DOCS_DIR` | The trimmed `source-dir` |
| `MDD_OUTPUT_DIR` | `/mdd-work/mdd-out` |
| `MDD_BASE_PATH` | The resolved base path |
| `MDD_SOURCE_SHA` | `GITHUB_SHA` when it matches 40 lowercase hexadecimal characters. Otherwise the value is empty. |

If `MDD_PROJECT_DIR`, `MDD_OUTPUT_DIR`, or `MDD_BASE_PATH` is empty, `scripts/mdd-build.mjs` prints this line and exits:

```text
MDD_PROJECT_DIR, MDD_OUTPUT_DIR, and MDD_BASE_PATH are required.
```

The shell script sets all three before it starts the container.

The build script prints each MDD diagnostic as `file:line: severity code: message`. A diagnostic with no file omits the location prefix. If MDD returns no site, the script prints this line and exits:

```text
MDD did not produce a site. Fix the documentation errors and run again.
```

A successful build prints a count and a directory:

```text
Built 6 pages into /mdd-work/mdd-out.
```

The number is the MDD page count. With the mount above, the directory is `/mdd-work/mdd-out`.

`place_docs` in `scripts/lib.sh` then requires `index.html` in the MDD output. If it is missing, the action stops with `MDD output has no index.html.`

The function deletes `.mdd-output.json` and copies the other build files.

| Mode | Copy |
| --- | --- |
| `standalone` | Delete every top-level entry in the site directory. Copy the build to the site root. |
| `workflow` | Replace the `docs-path` directory. Leave the rest of the site in place. |

In workflow mode an empty docs path stops with `docs-path is required when Pages already has a site.` The action writes an empty docs path only in standalone mode. Standalone mode copies to the site root and skips that check.

A symlink at the docs path stops with `Refusing to replace the symlink at docs.` Any other non-directory stops with `docs exists and is not a directory.` The existing path is left in place.

On success the log text is `Placed the docs into the Pages site.`

## Package and upload

`scripts/package-site.sh` requires Linux and `tar`. It requires `index.html` at the site root. If that file is missing, it stops with `The Pages site has no index.html.`

It writes `artifact.tar` under the work directory. The tar is created from the site directory with `--dereference`, `--hard-dereference`, `--exclude=.git`, and `--exclude=.github`.

On success the log text is `Packaged the Pages artifact.`

The upload step uses these settings:

| Setting | Value |
| --- | --- |
| `name` | `github-pages` |
| `path` | The `artifact.tar` from the package step |
| `retention-days` | `1` |
| `if-no-files-found` | `error` |
| `overwrite` | `true` |

The action output `artifact-name` is the constant `github-pages`.

## Errors

Validation errors for inputs are listed on [Inputs and outputs](./inputs-outputs.md). These are the other stop conditions. The quoted text is the message. The scripts also print a color prefix.

| Condition | Error text |
| --- | --- |
| `uname -s` is not `Linux` | `This action requires a Linux runner.` |
| A required command is missing | `Required command not found: docker` |
| `GITHUB_REPOSITORY` is unset | `Set GITHUB_REPOSITORY to owner/repo.` |
| `GITHUB_WORKSPACE` is unset | `Set GITHUB_WORKSPACE. Checkout the repository before this action.` |
| `github-token` is empty during resolve | `github-token is required to read GitHub Pages.` |
| Pages returns HTTP 401 or 403 | `Cannot read GitHub Pages (HTTP 401). Grant this job pages: read.` |
| Pages returns another non-200 status, except 404 | `GitHub Pages request failed with HTTP 500.` |
| Pages returns HTTP 200 with invalid JSON | `GitHub Pages returned invalid JSON.` |
| `build_type` is `legacy` | The three lines under [Pages source](../get-started/index.md#pages-source). |
| `build_type` is missing or unsupported | `Unsupported GitHub Pages build type: unknown.` |
| `GITHUB_OUTPUT` is unset | `GITHUB_OUTPUT is not set.` |
| The mode is not `standalone` or `workflow` | `Unknown Pages mode: other.` |
| `github-token` is empty during download | `github-token is required to download the Pages artifact.` |
| `GITHUB_RUN_ID` or `GITHUB_REPOSITORY` is unset during download | `GITHUB_RUN_ID and GITHUB_REPOSITORY are required.` |
| The artifact list is not HTTP 200 | `Cannot list workflow artifacts (HTTP 403). Grant this job actions: read.` |
| The artifact list is invalid JSON | `The artifact list was not valid JSON.` |
| The list reaches page 21 | `Stopped after 20 pages of workflow artifacts.` |
| No current `github-pages` artifact | `No github-pages artifact exists in this workflow run.` and `Run actions/upload-pages-artifact before this action.` |
| The download redirects without a location | `Artifact download redirected without a location.` |
| The redirect URL is not HTTPS | `Artifact download redirected to a non-HTTPS URL.` |
| The download returns HTTP 401 or 403 | `Cannot download the Pages artifact (HTTP 401). Grant this job actions: read.` |
| The download returns another error status | `Artifact download failed with HTTP 500.` |
| The zip has no top-level `artifact.tar` | `The github-pages artifact has no artifact.tar. Run actions/upload-pages-artifact before this action.` |
| A tar entry is unsafe | `Pages artifact contains an unsafe path: ../evil.txt` |
| `source-dir` is not a directory in the workspace | `source-dir mdd does not exist in the workspace.` and `An MDD folder needs contents/index.md. Checkout the repository before this action.` |
| The MDD folder fails the image check | `MDD_DOCS_DIR=mdd is not an MDD folder: mdd/contents/index.md is missing. An MDD folder needs contents/index.md (or the index.md of paths.contents in its config.json). config.json is optional.` |
| MDD prints diagnostics and returns no site | `MDD did not produce a site. Fix the documentation errors and run again.` |
| The MDD output has no `index.html` | `MDD output has no index.html.` |
| Workflow mode has an empty docs path | `docs-path is required when Pages already has a site.` |
| The docs path is a symlink | `Refusing to replace the symlink at docs.` |
| The docs path exists and is not a directory | `docs exists and is not a directory.` |
| The site root has no `index.html` | `The Pages site has no index.html.` |

Replace `docker`, `mdd`, `docs`, `401`, `403`, `500`, `unknown`, `other`, and `../evil.txt` with the command, path, status, or entry from the run.

A workflow `base-path` that does not end with the docs path is a warning. The action continues. The text is on [the existing-site page](../get-started/existing-site.md#base-path).

## Next

[Set inputs and read outputs](./inputs-outputs.md).
