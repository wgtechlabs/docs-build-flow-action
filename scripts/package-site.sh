#!/usr/bin/env bash
# Pack the merged site the same way actions/upload-pages-artifact does.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_linux

site="${SITE_DIR:?Set SITE_DIR.}"
root="$(work_dir)"
archive="${root}/artifact.tar"

package_site_tar "$site" "$archive"
log_success "Packaged the Pages artifact."
set_output "archive" "$archive"
