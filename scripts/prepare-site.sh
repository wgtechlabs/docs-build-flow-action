#!/usr/bin/env bash
# Create the site directory. In workflow mode, fill it from the current run's Pages artifact.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_linux

mode="${PAGES_MODE:?Set PAGES_MODE to standalone or workflow.}"
if [[ "$mode" != "standalone" && "$mode" != "workflow" ]]; then
  log_error "Unknown Pages mode: ${mode}"
  exit 1
fi

root="$(work_dir)"
site="${root}/site"
rm -rf "$site"
mkdir -p "$site"

download_artifact_zip() {
  local id="$1"
  local dest="$2"
  local api headers body code location

  require_cmd curl
  api="${GITHUB_API_URL:-https://api.github.com}"
  headers="$(mktemp)"
  body="$(mktemp)"
  code="$(
    curl -sS -D "$headers" -o "$body" -w '%{http_code}' \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api}/repos/${GITHUB_REPOSITORY}/actions/artifacts/${id}/zip"
  )"
  case "$code" in
    200)
      cp "$body" "$dest"
      ;;
    301|302|303|307|308)
      location="$(awk 'tolower($1) == "location:" { print $2 }' "$headers" | tr -d '\r' | tail -n 1)"
      if [[ -z "$location" ]]; then
        log_error "Artifact download redirected without a location."
        return 1
      fi
      if [[ "$location" != https://* ]]; then
        log_error "Artifact download redirected to a non-HTTPS URL."
        return 1
      fi
      curl -fsSL "$location" -o "$dest"
      ;;
    401|403)
      log_error "Cannot download the Pages artifact (HTTP ${code}). Grant this job actions: read."
      return 1
      ;;
    *)
      log_error "Artifact download failed with HTTP ${code}."
      return 1
      ;;
  esac
  rm -f "$headers" "$body"
}

latest_pages_artifact_id() {
  local api page body code count found created best_id best_created
  api="${GITHUB_API_URL:-https://api.github.com}"
  page=1
  best_id=""
  best_created=""

  while true; do
    body="$(mktemp)"
    code="$(
      curl -sS -o "$body" -w '%{http_code}' \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts?per_page=100&page=${page}"
    )"
    if [[ "$code" != "200" ]]; then
      log_error "Cannot list workflow artifacts (HTTP ${code}). Grant this job actions: read."
      return 1
    fi
    if ! jq empty "$body" >/dev/null 2>&1; then
      log_error "The artifact list was not valid JSON."
      return 1
    fi
    found="$(
      jq -r --arg name "$PAGES_ARTIFACT_NAME" '
        [.artifacts[]? | select(.name == $name and .expired == false)]
        | sort_by(.created_at)
        | last
        | if . == null then "" else "\(.id) \(.created_at)" end
      ' "$body"
    )"
    if [[ -n "$found" ]]; then
      created="${found#* }"
      if [[ -z "$best_created" || "$created" > "$best_created" ]]; then
        best_created="$created"
        best_id="${found%% *}"
      fi
    fi
    count="$(jq -r '.artifacts | length' "$body")"
    rm -f "$body"
    if [[ "$count" -lt 100 ]]; then
      break
    fi
    page=$((page + 1))
    if [[ "$page" -gt 20 ]]; then
      log_error "Stopped after 20 pages of workflow artifacts."
      return 1
    fi
  done

  if [[ ! "$best_id" =~ ^[0-9]+$ ]]; then
    log_error "No ${PAGES_ARTIFACT_NAME} artifact exists in this workflow run."
    log_error "Run actions/upload-pages-artifact before this action."
    return 1
  fi
  printf '%s\n' "$best_id"
}

if [[ "$mode" == "workflow" ]]; then
  zip="${root}/github-pages.zip"
  if [[ -n "${PAGES_ARTIFACT_ZIP:-}" ]]; then
    cp "$PAGES_ARTIFACT_ZIP" "$zip"
  else
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
      log_error "github-token is required to download the Pages artifact."
      exit 1
    fi
    if [[ -z "${GITHUB_RUN_ID:-}" || -z "${GITHUB_REPOSITORY:-}" ]]; then
      log_error "GITHUB_RUN_ID and GITHUB_REPOSITORY are required."
      exit 1
    fi
    require_cmd jq
    artifact_id="$(latest_pages_artifact_id)"
    log_info "Downloading ${PAGES_ARTIFACT_NAME} artifact ${artifact_id}."
    download_artifact_zip "$artifact_id" "$zip"
  fi
  extract_pages_zip "$zip" "$site"
  log_success "Extracted the current Pages artifact."
else
  log_info "No Pages site found. The docs will be the whole site."
fi

set_output "site-dir" "$site"
