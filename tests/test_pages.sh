#!/usr/bin/env bash
# Tests for Pages mode, base path, site merge, and artifact packaging.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

test_count=0
passed_count=0
failed_count=0

pass() {
  echo -e "${GREEN}✓${NC} Test ${test_count}: $1"
  passed_count=$((passed_count + 1))
}

fail() {
  echo -e "${RED}✗${NC} Test ${test_count}: $1"
  failed_count=$((failed_count + 1))
}

expect_success() {
  local name="$1"
  shift
  test_count=$((test_count + 1))
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
}

expect_failure() {
  local name="$1"
  shift
  test_count=$((test_count + 1))
  if "$@" >/dev/null 2>&1; then
    fail "$name"
  else
    pass "$name"
  fi
}

expect_eq() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  test_count=$((test_count + 1))
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "${name} (got ${actual}, expected ${expected})"
  fi
}

expect_file() {
  local name="$1"
  local file="$2"
  local expected="$3"
  test_count=$((test_count + 1))
  if [[ -f "$file" && "$(cat "$file")" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

write_json() {
  local file="$1"
  local json="$2"
  printf '%s\n' "$json" > "$file"
}

run_resolve() {
  local status="$1"
  local json="$2"
  local repository="$3"
  local base_path="${4-}"
  local docs_path="${5:-docs}"
  local source_dir="${6:-mdd}"
  local version="${7:-0.3.0}"
  local artifact="${8:-true}"
  local body output
  body="$(mktemp)"
  output="$(mktemp)"
  write_json "$body" "$json"
  set +e
  PAGES_HTTP_STATUS="$status" \
    PAGES_BODY_FILE="$body" \
    GITHUB_REPOSITORY="$repository" \
    GITHUB_OUTPUT="$output" \
    INPUT_BASE_PATH="$base_path" \
    INPUT_DOCS_PATH="$docs_path" \
    INPUT_SOURCE_DIR="$source_dir" \
    INPUT_MDD_VERSION="$version" \
    PAGES_ARTIFACT_PRESENT="$artifact" \
    bash "${ROOT}/scripts/resolve-pages.sh" >"${output}.log" 2>&1
  local code=$?
  set -e
  printf '%s\n' "$code"
  cat "$output"
}

output_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '
    $1 == key { value = substr($0, index($0, "=") + 1) }
    END { print value }
  ' "$file"
}

echo "=== Pages mode and site files ==="
echo

result="$(mktemp)"
run_resolve 404 '{"message":"Not Found"}' "wgtechlabs/docs-build-flow-action" > "$result"
expect_eq "missing Pages site is standalone" "$(sed -n '1p' "$result")" "0"
expect_eq "project site base path is /<repo>/" "$(output_value "$result" base-path)" "/docs-build-flow-action/"
expect_eq "standalone does not nest docs" "$(output_value "$result" docs-path)" ""

run_resolve 404 '{"message":"Not Found"}' "wgtechlabs/wgtechlabs.github.io" > "$result"
expect_eq "user site base path is /" "$(output_value "$result" base-path)" "/"

run_resolve 200 '{"build_type":"workflow","cname":null}' "wgtechlabs/docs-build-flow-action" > "$result"
expect_eq "workflow mode is selected" "$(output_value "$result" mode)" "workflow"
expect_eq "project docs base path includes docs-path" "$(output_value "$result" base-path)" "/docs-build-flow-action/docs/"
expect_eq "workflow keeps docs-path" "$(output_value "$result" docs-path)" "docs"

run_resolve 200 '{"build_type":"workflow","cname":null}' "wgtechlabs/docs-build-flow-action" "" docs mdd 0.3.0 false > "$result"
expect_eq "Pages site without an artifact is standalone" "$(output_value "$result" mode)" "standalone"
expect_eq "standalone with Pages uses /<repo>/" "$(output_value "$result" base-path)" "/docs-build-flow-action/"
expect_eq "standalone with Pages does not nest docs" "$(output_value "$result" docs-path)" ""

run_resolve 200 '{"build_type":"workflow","cname":"docs.example.com"}' "wgtechlabs/docs-build-flow-action" > "$result"
expect_eq "custom domain base path omits the repo" "$(output_value "$result" base-path)" "/docs/"

run_resolve 200 '{"build_type":"workflow","cname":null}' "acme/acme.github.io" "" "guides" > "$result"
expect_eq "user site docs use /<docs-path>/" "$(output_value "$result" base-path)" "/guides/"

run_resolve 200 '{"build_type":"workflow","cname":null}' "wgtechlabs/docs-build-flow-action" "guide" > "$result"
expect_eq "base-path override is normalized" "$(output_value "$result" base-path)" "/guide/"

legacy_body="$(mktemp)"
legacy_log="$(mktemp)"
printf '%s\n' '{"build_type":"legacy","cname":null}' > "$legacy_body"
set +e
PAGES_HTTP_STATUS=200 \
  PAGES_BODY_FILE="$legacy_body" \
  GITHUB_REPOSITORY="wgtechlabs/docs-build-flow-action" \
  GITHUB_OUTPUT="$(mktemp)" \
  INPUT_BASE_PATH="" \
  INPUT_DOCS_PATH="docs" \
  INPUT_SOURCE_DIR="mdd" \
  INPUT_MDD_VERSION="0.3.0" \
  bash "${ROOT}/scripts/resolve-pages.sh" >"$legacy_log" 2>&1
legacy_code=$?
set -e
test_count=$((test_count + 1))
if [[ "$legacy_code" -ne 0 ]] && grep -q "legacy build" "$legacy_log" && grep -q "GitHub Actions" "$legacy_log"; then
  pass "legacy Pages tells the user to switch to GitHub Actions"
else
  fail "legacy Pages tells the user to switch to GitHub Actions"
fi

invalid_body="$(mktemp)"
printf 'not-json\n' > "$invalid_body"
expect_failure "invalid Pages JSON fails" \
  env PAGES_HTTP_STATUS=200 PAGES_BODY_FILE="$invalid_body" \
    GITHUB_REPOSITORY="wgtechlabs/docs-build-flow-action" \
    GITHUB_OUTPUT="$(mktemp)" \
    INPUT_DOCS_PATH=docs INPUT_SOURCE_DIR=mdd INPUT_MDD_VERSION=0.3.0 INPUT_BASE_PATH= \
    bash "${ROOT}/scripts/resolve-pages.sh"

forbidden_body="$(mktemp)"
printf '%s\n' '{"message":"Resource not accessible by integration"}' > "$forbidden_body"
expect_failure "Pages permission failure is an error" \
  env PAGES_HTTP_STATUS=403 PAGES_BODY_FILE="$forbidden_body" \
    GITHUB_REPOSITORY="wgtechlabs/docs-build-flow-action" \
    GITHUB_OUTPUT="$(mktemp)" \
    INPUT_DOCS_PATH=docs INPUT_SOURCE_DIR=mdd INPUT_MDD_VERSION=0.3.0 INPUT_BASE_PATH= \
    bash "${ROOT}/scripts/resolve-pages.sh"

expect_failure "parent docs-path is rejected" \
  env PAGES_HTTP_STATUS=404 PAGES_BODY_FILE="$invalid_body" \
    GITHUB_REPOSITORY="wgtechlabs/docs-build-flow-action" \
    GITHUB_OUTPUT="$(mktemp)" \
    INPUT_DOCS_PATH=../docs INPUT_SOURCE_DIR=mdd INPUT_MDD_VERSION=0.3.0 INPUT_BASE_PATH= \
    bash "${ROOT}/scripts/resolve-pages.sh"

expect_failure "image tag cannot change the registry" \
  env PAGES_HTTP_STATUS=404 PAGES_BODY_FILE="$invalid_body" \
    GITHUB_REPOSITORY="wgtechlabs/docs-build-flow-action" \
    GITHUB_OUTPUT="$(mktemp)" \
    INPUT_DOCS_PATH=docs INPUT_SOURCE_DIR=mdd INPUT_MDD_VERSION='0.3.0/evil' INPUT_BASE_PATH= \
    bash "${ROOT}/scripts/resolve-pages.sh"

expect_success "pinned image tag is valid" image_ref 0.3.0
expect_eq "image reference stays on wgtechlabs/mdd" "$(image_ref 0.3.0)" "wgtechlabs/mdd:0.3.0"

temp_root="$(mktemp -d)"
site="${temp_root}/site"
docs_out="${temp_root}/out"
mkdir -p "$site" "$docs_out"
printf 'home\n' > "${site}/index.html"
printf 'docs\n' > "${docs_out}/index.html"
printf '{}\n' > "${docs_out}/.mdd-output.json"
expect_success "workflow placement keeps the site root" \
  place_docs workflow "$site" "$docs_out" docs
expect_file "site root stays in place" "${site}/index.html" "home"
expect_file "docs are nested at docs-path" "${site}/docs/index.html" "docs"
test_count=$((test_count + 1))
if [[ ! -e "${site}/docs/.mdd-output.json" ]]; then
  pass "build inventory is not published"
else
  fail "build inventory is not published"
fi

printf 'only\n' > "${docs_out}/index.html"
expect_success "standalone placement replaces the site" \
  place_docs standalone "$site" "$docs_out" ""
expect_file "standalone docs become the site root" "${site}/index.html" "only"
test_count=$((test_count + 1))
if [[ ! -e "${site}/docs" ]]; then
  pass "standalone removes the previous nested docs"
else
  fail "standalone removes the previous nested docs"
fi

mkdir -p "$site"
printf 'file\n' > "${site}/docs"
expect_failure "a file at docs-path is rejected" \
  place_docs workflow "$site" "$docs_out" docs

rm -f "${site}/docs"
ln -s /tmp "${site}/docs"
expect_failure "a symlink at docs-path is rejected" \
  place_docs workflow "$site" "$docs_out" docs
test_count=$((test_count + 1))
if [[ -L "${site}/docs" ]]; then
  pass "rejected symlink is left in place"
else
  fail "rejected symlink is left in place"
fi

runner="$(mktemp -d)"
fixture="$(mktemp -d)"
mkdir -p "${fixture}/page"
printf 'home\n' > "${fixture}/page/index.html"
printf 'keep\n' > "${fixture}/page/.keep"
mkdir -p "${fixture}/page/.git"
printf 'secret\n' > "${fixture}/page/.git/config"
tar -C "${fixture}/page" -cf "${fixture}/artifact.tar" .
(cd "$fixture" && zip -q pages.zip artifact.tar)
output="$(mktemp)"
expect_success "workflow mode extracts the Pages artifact" \
  env PAGES_MODE=workflow PAGES_ARTIFACT_ZIP="${fixture}/pages.zip" \
    RUNNER_TEMP="$runner" GITHUB_OUTPUT="$output" \
    bash "${ROOT}/scripts/prepare-site.sh"
prepared="$(output_value "$output" site-dir)"
expect_file "extracted site keeps index.html" "${prepared}/index.html" "home"
expect_file "extracted site keeps hidden files" "${prepared}/.keep" "keep"

bad="$(mktemp -d)"
python3 - "$bad/artifact.tar" <<'PY'
import io
import sys
import tarfile

path = sys.argv[1]
payload = b"bad\n"
info = tarfile.TarInfo("../evil.txt")
info.size = len(payload)
with tarfile.open(path, "w") as archive:
    archive.addfile(info, io.BytesIO(payload))
PY
(cd "$bad" && zip -q bad.zip artifact.tar)
expect_failure "unsafe artifact paths are rejected" \
  env PAGES_MODE=workflow PAGES_ARTIFACT_ZIP="${bad}/bad.zip" \
    RUNNER_TEMP="$(mktemp -d)" GITHUB_OUTPUT="$(mktemp)" \
    bash "${ROOT}/scripts/prepare-site.sh"

workspace="$(mktemp -d)"
mkdir -p "${workspace}/mdd"
site_dir="$(mktemp -d)/site"
mkdir -p "$site_dir"
printf 'home\n' > "${site_dir}/index.html"
fake_bin="$(mktemp -d)"
docker_log="$(mktemp)"
cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${DOCKER_LOG:?}"
previous=""
parent=""
name=""
for arg in "$@"; do
  if [[ "$previous" == "-v" && "$arg" == *:/mdd-work ]]; then
    parent="${arg%:/mdd-work}"
  fi
  if [[ "$previous" == "-e" && "$arg" == MDD_OUTPUT_DIR=/mdd-work/* ]]; then
    name="${arg#MDD_OUTPUT_DIR=/mdd-work/}"
  fi
  previous="$arg"
done
if [[ -z "$parent" || -z "$name" ]]; then
  echo "missing output mount" >&2
  exit 1
fi
output="${parent}/${name}"
printf 'built\n' > "${output}/index.html"
printf '{}\n' > "${output}/.mdd-output.json"
EOF
chmod +x "${fake_bin}/docker"
build_output="$(mktemp)"
expect_success "build step merges fake MDD output" \
  env PATH="${fake_bin}:${PATH}" DOCKER_LOG="$docker_log" \
    PAGES_MODE=workflow BASE_PATH=/docs-build-flow-action/docs/ \
    SOURCE_DIR=mdd MDD_VERSION=0.3.0 SITE_DIR="$site_dir" DOCS_PATH=docs \
    GITHUB_WORKSPACE="$workspace" GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 \
    RUNNER_TEMP="$(mktemp -d)" GITHUB_OUTPUT="$build_output" \
    bash "${ROOT}/scripts/build-docs.sh"
expect_file "existing site page stays at /" "${site_dir}/index.html" "home"
expect_file "built docs land in docs/" "${site_dir}/docs/index.html" "built"
test_count=$((test_count + 1))
if grep -q "wgtechlabs/mdd:0.3.0" "$docker_log" && grep -q "/opt/mdd-build.mjs" "$docker_log"; then
  pass "build invokes the pinned image entry"
else
  fail "build invokes the pinned image entry"
fi

package_output="$(mktemp)"
package_runner="$(mktemp -d)"
expect_success "site packages as artifact.tar" \
  env SITE_DIR="$site_dir" RUNNER_TEMP="$package_runner" GITHUB_OUTPUT="$package_output" \
    bash "${ROOT}/scripts/package-site.sh"
archive="$(output_value "$package_output" archive)"
list="$(tar -tf "$archive")"
test_count=$((test_count + 1))
if printf '%s\n' "$list" | grep -qx './index.html' && printf '%s\n' "$list" | grep -qx './docs/index.html'; then
  pass "archive contains the merged site"
else
  fail "archive contains the merged site"
fi
mkdir -p "${site_dir}/.git" "${site_dir}/.github"
printf 'x\n' > "${site_dir}/.git/config"
printf 'x\n' > "${site_dir}/.github/workflows.yml"
package_output="$(mktemp)"
expect_success "repackage excludes VCS metadata" \
  env SITE_DIR="$site_dir" RUNNER_TEMP="$package_runner" GITHUB_OUTPUT="$package_output" \
    bash "${ROOT}/scripts/package-site.sh"
list="$(tar -tf "$(output_value "$package_output" archive)")"
test_count=$((test_count + 1))
if printf '%s\n' "$list" | grep -q '\.git/' || printf '%s\n' "$list" | grep -q '\.github/'; then
  fail "archive excludes .git and .github"
else
  pass "archive excludes .git and .github"
fi

echo
echo "=== Results: ${passed_count}/${test_count} passed ==="
if [[ "$failed_count" -gt 0 ]]; then
  exit 1
fi
echo "All tests passed!"
