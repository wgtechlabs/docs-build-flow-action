---
title: Add docs to an existing site
navTitle: Existing site
order: 3
---
# Add docs to an existing site

Workflow mode copies the MDD build into one directory of a site that already exists.

The rest of that site stays in place. The action deletes the docs directory and copies the new files into it.

## When this mode runs

`scripts/resolve-pages.sh` selects workflow mode when both of these are true:

- `GET /repos/{owner}/{repo}/pages` returns HTTP 200.
- The JSON `build_type` is `workflow`.

The `docs-path` output is the docs path. The default is `docs`.

HTTP 404 uses [standalone mode](./standalone.md) instead. `build_type` `legacy` stops the action. The three log lines are on [Requirements](./index.md).

## Workflow

Upload a `github-pages` artifact before this action. The artifact must already exist in the same workflow run. `scripts/prepare-site.sh` lists artifacts for `GITHUB_RUN_ID`.

The example uploads that artifact in an earlier step of the same job. An earlier job in the same run also satisfies the check.

Save this file under `.github/workflows/`. The repository copy is `examples/workflow.yml`.

```yaml
name: Publish site and docs

on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: read
  actions: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deploy.outputs.page_url }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v7.0.1

      - name: Upload site
        uses: actions/upload-pages-artifact@v5.0.0
        with:
          path: ./site

      - name: Build docs into the site
        uses: wgtechlabs/docs-build-flow-action@v0
        with:
          source-dir: mdd
          docs-path: docs

      - name: Deploy Pages
        id: deploy
        uses: actions/deploy-pages@v5.0.1
```

`source-dir: mdd` and `docs-path: docs` repeat the defaults.

`actions/upload-pages-artifact@v5.0.0` must produce the artifact this action downloads. The zip must contain `artifact.tar` at its top level. The action looks only for the artifact name `github-pages`.

`actions/deploy-pages@v5.0.1` publishes the archive this action uploads afterward. The upload sets `overwrite: true`, so the new archive replaces the one from the upload step.

## Artifact rules

The action keeps an artifact when its name is `github-pages` and `expired` is false. If several match, it uses the one with the latest `created_at`.

It requests 100 artifacts per page. If it reaches page 21, it stops with this text:

```text
Stopped after 20 pages of workflow artifacts.
```

If none match, it stops with both of these lines:

```text
No github-pages artifact exists in this workflow run.
Run actions/upload-pages-artifact before this action.
```

The zip is opened with `unzip`. If `artifact.tar` is missing, the action stops with this text:

```text
The github-pages artifact has no artifact.tar. Run actions/upload-pages-artifact before this action.
```

Before it extracts the tar, it rejects an unsafe entry. An unsafe entry is absolute, contains `\`, or steps upward with `..`. The action stops with this text:

```text
Pages artifact contains an unsafe path: ../evil.txt
```

The path in the text is the archive entry. The tar is not extracted. The temporary directory is removed.

A download that returns HTTP 401 or HTTP 403 stops with this text:

```text
Cannot download the Pages artifact (HTTP 403). Grant this job actions: read.
```

The status in the text is the status GitHub returned. A list request that returns any status other than 200 stops with `Cannot list workflow artifacts (HTTP 403). Grant this job actions: read.` The status in that text is the status GitHub returned.

## Where the docs go

The extracted site must contain `index.html` at its root. Packaging checks that file after the docs are copied. The docs homepage is under the docs path. If the root file is missing, the action stops with this text:

```text
The Pages site has no index.html.
```

`docs-path` is the destination directory, relative to the site root.

| Path at `docs-path` | Result |
| --- | --- |
| Missing, or an existing directory | The action deletes that directory, creates it, and copies the MDD output into it. |
| A symlink | The action stops with `Refusing to replace the symlink at docs.` The symlink stays. |
| Any other existing file | The action stops with `docs exists and is not a directory.` The file stays. |

The path in those two errors is the `docs-path` value. `docs/api` is a valid docs path. The destination is then `docs/api` under the site root.

The action removes `.mdd-output.json` from the MDD output before the copy. `mdd-build.json` is copied with the docs.

The new archive omits `.git` and `.github`. It stores the files that symlinks point at. `scripts/package-site.sh` uses `tar --dereference --hard-dereference` with those two excludes.

## Base path

Leave `base-path` empty to use the prefix below. Workflow mode appends the docs path and a slash.

| Repository | `cname` | `docs-path` | Base path |
| --- | --- | --- | --- |
| `wgtechlabs/docs-build-flow-action` | null | `docs` | `/docs-build-flow-action/docs/` |
| `wgtechlabs/docs-build-flow-action` | `docs.example.com` | `docs` | `/docs/` |
| `acme/acme.github.io` | null | `guides` | `/guides/` |
| `wgtechlabs/docs-build-flow-action` | null | `docs/api` | `/docs-build-flow-action/docs/api/` |

A non-empty `cname` omits the repository name. Null, missing, and empty `cname` leave the repository name in place, unless the repository name matches `owner.github.io`.

In the example, `./site` stays at the site root. The docs directory is `docs`. On a project repository with no custom domain, the public prefix is `/docs-build-flow-action/docs/` when the repository name is `docs-build-flow-action`.

If you set `base-path` and it does not end with `/docs/`, the action warns and continues:

```text
base-path /guide/ does not end with /docs/. Page links may not match the published directory.
```

`/guide/` is the normalized base path. `/docs/` is the docs path with slashes. The files are still copied to the docs path.

## Next

Input rules and the full prefix table are on [Inputs and outputs](../usage/inputs-outputs.md). The download and upload steps are on [How it works](../usage/index.md).
