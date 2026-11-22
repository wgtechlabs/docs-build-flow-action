---
navTitle: Introduction
order: 0
---
# Docs Build Flow

Docs Build Flow Action builds an [MDD](https://github.com/wgtechlabs/mdd) folder into static files and uploads a `github-pages` artifact.

This action's last step is `actions/upload-artifact@v7.0.2`. The example workflows publish that artifact with `actions/deploy-pages` in a later step.

The current release is [v0.1.0](https://github.com/wgtechlabs/docs-build-flow-action/releases/tag/v0.1.0). The examples pin `wgtechlabs/docs-build-flow-action@v0`. The `v0` tag currently points at the same commit as `v0.1.0`.

## Modes

The action calls `GET /repos/{owner}/{repo}/pages`. That response, and whether this run has a `github-pages` artifact, select the mode. No input overrides it.

| Pages API result | Mode | What the action does |
| --- | --- | --- |
| HTTP 404 | `standalone` | The built docs become the whole site. |
| HTTP 200, `build_type` is `workflow`, and no `github-pages` artifact in this run | `standalone` | The built docs become the whole site. |
| HTTP 200, `build_type` is `workflow`, and a `github-pages` artifact in this run | `workflow` | The action merges the docs into the `github-pages` artifact from the same run. |
| HTTP 200 and `build_type` is `legacy` | The action stops | The log tells you to set the Pages source to GitHub Actions. |
| Another HTTP status, or another `build_type` | The action stops | The log includes the status or the build type. |

## What it writes

- MDD receives one public base path. Page links use that prefix.
- Workflow mode replaces the docs directory inside the existing site. The other site files stay.
- The upload uses artifact name `github-pages`, `overwrite: true`, and `retention-days: 1`.

## Where to start

1. [Check the requirements](./get-started/index.md).
2. [Publish the docs as the whole site](./get-started/standalone.md).
3. [Add the docs to an existing site](./get-started/existing-site.md).
4. [Follow the build steps](./usage/index.md).
5. [Set inputs and read outputs](./usage/inputs-outputs.md).
