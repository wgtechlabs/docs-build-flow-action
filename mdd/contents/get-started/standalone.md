---
title: Publish docs as the whole site
navTitle: Standalone site
order: 2
---
# Publish docs as the whole site

Standalone mode publishes the MDD build as the whole Pages site.

The built files are copied to the site root. `docs-path` is still validated, and the `docs-path` output is an empty string.

## When this mode runs

`scripts/resolve-pages.sh` selects standalone mode when `GET /repos/{owner}/{repo}/pages` returns HTTP 404.

The Pages response body is not read on HTTP 404. Standalone mode has no `cname` and no `build_type`.

> [!IMPORTANT]
> The Pages response selects the mode. A later run that returns HTTP 200 with `build_type` `workflow` uses workflow mode.
> Workflow mode requires a `github-pages` artifact that already exists in that run.
> The workflow on this page does not upload one.
> That run stops with `No github-pages artifact exists in this workflow run.`

For a repository that already has a GitHub Actions Pages site, use [an existing site](./existing-site.md).

## Base path

Leave `base-path` empty. The action then sets the prefix.

| Repository | Base path |
| --- | --- |
| `wgtechlabs/docs-build-flow-action` | `/docs-build-flow-action/` |
| `WGTechLabs/Docs-Build-Flow-Action` | `/Docs-Build-Flow-Action/` |
| `wgtechlabs/wgtechlabs.github.io` | `/` |
| `Acme/ACME.github.io` | `/` |
| `acme/docs.github.io` | `/docs.github.io/` |

The repository name is compared, in lowercase, with `owner.github.io`. `owner` is the text before the slash in `GITHUB_REPOSITORY`.

When the names match, the base path is `/`. When they differ, the base path is `/`, the repository name as written, and `/`.

`docs-path` is not added in standalone mode. With input `guides` and an empty `base-path`, repository `wgtechlabs/docs-build-flow-action` still gets `/docs-build-flow-action/`, and the `docs-path` output is empty.

A set `base-path` replaces this rule. The action adds a leading `/` and a trailing `/` when they are missing. See [Inputs and outputs](../usage/inputs-outputs.md).

## Workflow

Save this file under `.github/workflows/`. The repository copy is `examples/standalone.yml`.

```yaml
name: Publish docs

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

      - name: Build docs
        uses: wgtechlabs/docs-build-flow-action@v0
        with:
          source-dir: mdd

      - name: Deploy Pages
        id: deploy
        uses: actions/deploy-pages@v5.0.1
```

The example runs on a push to `main`. Change `branches` when you deploy a different branch.

`source-dir: mdd` repeats the default. You can omit it.

The job environment is `github-pages`. Its URL is `steps.deploy.outputs.page_url` from `actions/deploy-pages`. That output belongs to the deploy step, not to this action.

`actions/deploy-pages@v5.0.1` is the step that publishes the artifact.

## What gets published

`scripts/prepare-site.sh` starts from an empty site directory. Its log text is:

```text
No Pages site found. The docs will be the whole site.
```

`scripts/build-docs.sh` copies the MDD output into that directory. It first removes every top-level entry in the site directory. It also removes `.mdd-output.json` from the MDD output, so that file is not copied.

The copy includes `mdd-build.json`. That file records `schemaVersion`, `mddVersion`, `engineVersion`, `basePath`, and `source`. When `GITHUB_SHA` is 40 lowercase hexadecimal characters, `source.commit` is that SHA. `source.dirty` is null.

`scripts/package-site.sh` then requires `index.html` at the site root. The MDD homepage supplies that file. If it is missing, the action stops with `MDD output has no index.html.`

The packaged archive is uploaded as `github-pages`.

## Next

[Add the docs to an existing site](./existing-site.md) when the Pages API returns workflow mode. The step list is on [How it works](../usage/index.md).
