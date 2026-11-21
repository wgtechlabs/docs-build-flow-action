#!/usr/bin/env bash
# Build the MDD folder with the pinned image and place the files in the site.
#
# wgtechlabs/mdd has no static-export command. The image compiles with build()
# and then starts the server. This step calls that build() export and exits.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_linux
require_cmd docker

mode="${PAGES_MODE:?Set PAGES_MODE.}"
base_path="${BASE_PATH:?Set BASE_PATH.}"
source_dir="$(trim "${SOURCE_DIR:?Set SOURCE_DIR.}")"
mdd_version="$(trim "${MDD_VERSION:?Set MDD_VERSION.}")"
site="${SITE_DIR:?Set SITE_DIR.}"
docs_path="$(trim "${DOCS_PATH:-}")"
workspace="${GITHUB_WORKSPACE:?Set GITHUB_WORKSPACE. Checkout the repository before this action.}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

validate_relative_path "$source_dir" "source-dir"
validate_base_path "$base_path"
image="$(image_ref "$mdd_version")"

if [[ ! -d "$site" ]]; then
  log_error "Site directory does not exist: ${site}"
  exit 1
fi
if [[ ! -d "${workspace}/${source_dir}" ]]; then
  log_error "source-dir ${source_dir} does not exist in the workspace."
  log_error "An MDD folder needs contents/index.md. Checkout the repository before this action."
  exit 1
fi

root="$(work_dir)"
output="${root}/mdd-out"
rm -rf "$output"
mkdir -p "$output"

source_sha=""
if [[ "${GITHUB_SHA:-}" =~ ^[a-f0-9]{40}$ ]]; then
  source_sha="$GITHUB_SHA"
fi

# MDD renames the output directory and writes a sibling lock. Mount the parent
# so both stay on a writable volume. Mounting the output directory itself fails.
parent="$(dirname "$output")"
name="$(basename "$output")"
if [[ "$parent" == "/" || "$name" == .* || "$name" == *[!A-Za-z0-9._-]* ]]; then
  log_error "MDD output directory must sit in a writable folder."
  exit 1
fi

log_info "Building docs with ${image} at ${base_path}."
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --entrypoint node \
  -e HOME=/tmp \
  -v "${workspace}:/workspace:ro" \
  -v "${parent}:/mdd-work" \
  -v "${script_dir}/mdd-build.mjs:/opt/mdd-build.mjs:ro" \
  -e MDD_PROJECT_DIR=/workspace \
  -e MDD_DOCS_DIR="${source_dir}" \
  -e "MDD_OUTPUT_DIR=/mdd-work/${name}" \
  -e MDD_BASE_PATH="${base_path}" \
  -e MDD_SOURCE_SHA="${source_sha}" \
  "$image" \
  /opt/mdd-build.mjs

place_docs "$mode" "$site" "$output" "$docs_path"
log_success "Placed the docs into the Pages site."
set_output "site-dir" "$site"
