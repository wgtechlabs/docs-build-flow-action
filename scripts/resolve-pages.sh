#!/usr/bin/env bash
# Read the Pages site and choose standalone or workflow mode.
# Workflow mode needs a Pages artifact from an earlier step in this run.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd jq

repository="${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY to owner/repo.}"
owner="${repository%%/*}"
repo_name="${repository#*/}"
docs_path="$(trim "${INPUT_DOCS_PATH:-docs}")"
source_dir="$(trim "${INPUT_SOURCE_DIR:-mdd}")"
mdd_version="$(trim "${INPUT_MDD_VERSION:-0.3.0}")"
base_override="$(trim "${INPUT_BASE_PATH:-}")"

validate_relative_path "$docs_path" "docs-path"
validate_relative_path "$source_dir" "source-dir"
validate_image_tag "$mdd_version"

body_file=""
http_code=""
if [[ -n "${PAGES_HTTP_STATUS:-}" && -n "${PAGES_BODY_FILE:-}" ]]; then
  http_code="$PAGES_HTTP_STATUS"
  body_file="$PAGES_BODY_FILE"
else
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log_error "github-token is required to read GitHub Pages."
    exit 1
  fi
  require_cmd curl
  body_file="$(mktemp)"
  api="${GITHUB_API_URL:-https://api.github.com}"
  http_code="$(
    curl -sS -o "$body_file" -w '%{http_code}' \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api}/repos/${repository}/pages"
  )"
fi

pages_from_response "$http_code" "$body_file" "$repository"
if [[ "$PAGES_MODE" == "workflow" ]]; then
  has_artifact="$(run_has_pages_artifact)"
  if [[ "$has_artifact" != "true" ]]; then
    log_info "No ${PAGES_ARTIFACT_NAME} artifact in this run. The docs will be the whole site."
    PAGES_MODE="standalone"
  fi
fi
base_path="$(compute_base_path "$PAGES_MODE" "$base_override" "$docs_path" "$owner" "$repo_name" "$PAGES_CNAME")"
placement="$docs_path"
if [[ "$PAGES_MODE" == "standalone" ]]; then
  placement=""
fi

log_success "Pages mode is ${PAGES_MODE}. Base path is ${base_path}."
set_output "mode" "$PAGES_MODE"
set_output "base-path" "$base_path"
set_output "docs-path" "$placement"
set_output "source-dir" "$source_dir"
set_output "mdd-version" "$mdd_version"
