#!/usr/bin/env bash
# Shared checks for the docs Pages build.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PAGES_ARTIFACT_NAME="github-pages"

log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}" >&2
}

log_error() {
  echo -e "${RED}❌ $1${NC}" >&2
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required command not found: ${cmd}"
    return 1
  fi
}

require_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "This action requires a Linux runner."
    return 1
  fi
}

trim() {
  local value="$1"
  printf '%s\n' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

validate_relative_path() {
  local value="$1"
  local label="$2"
  local segment
  local -a parts=()

  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
    log_error "${label} must be a relative path such as mdd or docs."
    return 1
  fi

  IFS='/' read -ra parts <<< "$value"
  for segment in "${parts[@]}"; do
    if [[ "$segment" == .* || "$segment" == ".git" || "$segment" == ".github" ]]; then
      log_error "${label} cannot contain a hidden path segment."
      return 1
    fi
  done
}

validate_image_tag() {
  local value="$1"
  if [[ ! "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    log_error "mdd-version must be a Docker tag such as 0.3.0."
    return 1
  fi
}

image_ref() {
  local tag="$1"
  validate_image_tag "$tag" || return 1
  printf 'wgtechlabs/mdd:%s\n' "$tag"
}

validate_base_path() {
  local value="$1"
  local segment
  local rest
  local -a parts=()

  if [[ "$value" == "/" ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^(/[A-Za-z0-9._-]+)+/$ ]]; then
    log_error "base-path must look like /, /docs/, or /repo/docs/."
    return 1
  fi

  rest="${value#/}"
  rest="${rest%/}"
  IFS='/' read -ra parts <<< "$rest"
  for segment in "${parts[@]}"; do
    if [[ "$segment" == "." || "$segment" == ".." || "$segment" == .* ]]; then
      log_error "base-path cannot contain a hidden or parent segment."
      return 1
    fi
  done
}

normalize_base_path() {
  local value
  value="$(trim "$1")"
  if [[ -z "$value" ]]; then
    log_error "base-path cannot be empty when it is set."
    return 1
  fi
  if [[ "$value" != /* ]]; then
    value="/${value}"
  fi
  if [[ "$value" != */ ]]; then
    value="${value}/"
  fi
  validate_base_path "$value" || return 1
  printf '%s\n' "$value"
}

# Prints the public MDD base path.
# standalone publishes the docs as the whole site.
# workflow publishes them under docs-path.
compute_base_path() {
  local mode="$1"
  local override="$2"
  local docs_path="$3"
  local owner="$4"
  local repo_name="$5"
  local cname="$6"
  local normalized="/"
  local repo_lower
  local owner_site_lower
  local path="/"

  if [[ -n "$override" ]]; then
    normalized="$(normalize_base_path "$override")" || return 1
    if [[ "$mode" == "workflow" && "$normalized" != */"${docs_path}/" ]]; then
      log_warning "base-path ${normalized} does not end with /${docs_path}/. Page links may not match the published directory."
    fi
    printf '%s\n' "$normalized"
    return 0
  fi

  repo_lower="$(printf '%s' "$repo_name" | tr '[:upper:]' '[:lower:]')"
  owner_site_lower="$(printf '%s' "${owner}.github.io" | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$cname" && "$repo_lower" != "$owner_site_lower" ]]; then
    path="/${repo_name}/"
  fi
  if [[ "$mode" == "workflow" ]]; then
    path="${path}${docs_path}/"
  fi
  validate_base_path "$path" || return 1
  printf '%s\n' "$path"
}

# Prints true when this workflow run has a Pages artifact, otherwise false.
# PAGES_ARTIFACT_PRESENT overrides the API check.
run_has_pages_artifact() {
  local api body code count

  if [[ -n "${PAGES_ARTIFACT_PRESENT:-}" ]]; then
    [[ "$PAGES_ARTIFACT_PRESENT" == "true" ]] && echo true || echo false
    return 0
  fi
  if [[ -z "${GITHUB_TOKEN:-}" || -z "${GITHUB_RUN_ID:-}" ]]; then
    log_error "github-token and GITHUB_RUN_ID are required to check for a Pages artifact."
    return 1
  fi
  require_cmd curl
  api="${GITHUB_API_URL:-https://api.github.com}"
  body="$(mktemp)"
  code="$(
    curl -sS -o "$body" -w '%{http_code}' \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts?name=${PAGES_ARTIFACT_NAME}"
  )"
  if [[ "$code" != "200" ]] || ! jq empty "$body" >/dev/null 2>&1; then
    rm -f "$body"
    log_error "Cannot list workflow artifacts (HTTP ${code}). Grant this job actions: read."
    return 1
  fi
  count="$(jq '[.artifacts[]? | select(.expired == false)] | length' "$body")"
  rm -f "$body"
  [[ "$count" -gt 0 ]] && echo true || echo false
}

# Sets PAGES_MODE and PAGES_CNAME. Returns 1 for legacy and request failures.
pages_from_response() {
  local code="$1"
  local file="$2"
  local build_type
  local repository="${3:-this repository}"

  PAGES_MODE=""
  PAGES_CNAME=""

  case "$code" in
    404)
      PAGES_MODE="standalone"
      return 0
      ;;
    200)
      ;;
    401|403)
      log_error "Cannot read GitHub Pages (HTTP ${code}). Grant this job pages: read."
      return 1
      ;;
    *)
      log_error "GitHub Pages request failed with HTTP ${code}."
      return 1
      ;;
  esac

  if ! jq empty "$file" >/dev/null 2>&1; then
    log_error "GitHub Pages returned invalid JSON."
    return 1
  fi

  build_type="$(jq -r '.build_type // empty' "$file")"
  PAGES_CNAME="$(jq -r '.cname // empty' "$file")"
  case "$build_type" in
    workflow)
      PAGES_MODE="workflow"
      ;;
    legacy)
      log_error "GitHub Pages for ${repository} uses the legacy build."
      log_error "Set the Pages source to GitHub Actions: https://github.com/${repository}/settings/pages"
      log_error "Then run this action after actions/upload-pages-artifact and before actions/deploy-pages."
      return 1
      ;;
    *)
      log_error "Unsupported GitHub Pages build type: ${build_type:-unknown}."
      return 1
      ;;
  esac
}

reject_unsafe_tar() {
  local archive="$1"
  local entry

  require_cmd tar || return 1
  while IFS= read -r entry; do
    entry="${entry#./}"
    entry="${entry%/}"
    if [[ -z "$entry" ]]; then
      continue
    fi
    if [[ "$entry" == /* || "$entry" == ".." || "$entry" == ../* || "$entry" == */.. || "$entry" == */../* || "$entry" == *\\* ]]; then
      log_error "Pages artifact contains an unsafe path: ${entry}"
      return 1
    fi
  done < <(tar -tf "$archive")
}

extract_pages_zip() {
  local zip="$1"
  local site="$2"
  local work
  local archive

  require_cmd unzip || return 1
  require_cmd tar || return 1
  work="$(mktemp -d)"
  unzip -q "$zip" -d "$work"
  if [[ ! -f "${work}/artifact.tar" ]]; then
    rm -rf "$work"
    log_error "The github-pages artifact has no artifact.tar. Run actions/upload-pages-artifact before this action."
    return 1
  fi
  archive="${work}/artifact.tar"
  if ! reject_unsafe_tar "$archive"; then
    rm -rf "$work"
    return 1
  fi
  mkdir -p "$site"
  tar -xf "$archive" -C "$site"
  rm -rf "$work"
}

place_docs() {
  local mode="$1"
  local site="$2"
  local docs_out="$3"
  local docs_path="$4"
  local dest

  if [[ ! -f "${docs_out}/index.html" ]]; then
    log_error "MDD output has no index.html."
    return 1
  fi
  rm -f "${docs_out}/.mdd-output.json"

  if [[ "$mode" == "standalone" ]]; then
    find "$site" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "${docs_out}/." "$site/"
    return 0
  fi

  if [[ -z "$docs_path" ]]; then
    log_error "docs-path is required when Pages already has a site."
    return 1
  fi

  dest="${site}/${docs_path}"
  if [[ -L "$dest" ]]; then
    log_error "Refusing to replace the symlink at ${docs_path}."
    return 1
  fi
  if [[ -e "$dest" && ! -d "$dest" ]]; then
    log_error "${docs_path} exists and is not a directory."
    return 1
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "${docs_out}/." "$dest/"
}

package_site_tar() {
  local site="$1"
  local archive="$2"

  require_cmd tar || return 1
  if [[ ! -f "${site}/index.html" ]]; then
    log_error "The Pages site has no index.html."
    return 1
  fi
  mkdir -p "$(dirname "$archive")"
  rm -f "$archive"
  tar \
    --dereference \
    --hard-dereference \
    --directory "$site" \
    -cf "$archive" \
    --exclude=.git \
    --exclude=.github \
    .
}

set_output() {
  local name="$1"
  local value="$2"
  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    log_error "GITHUB_OUTPUT is not set."
    return 1
  fi
  printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT"
}

work_dir() {
  local root="${RUNNER_TEMP:-/tmp}/docs-build-flow"
  mkdir -p "$root"
  printf '%s\n' "$root"
}
