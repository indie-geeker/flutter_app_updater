#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
temporary_root="$(mktemp -d)"
package_root="${temporary_root}/package"
publish_log="${temporary_root}/publish.log"

cleanup() {
  rm -rf "${temporary_root}"
}
trap cleanup EXIT

mkdir -p "${package_root}"
(cd "${repository_root}" && git archive HEAD) | tar -x -C "${package_root}"

cd "${package_root}"
flutter pub get

set +e
flutter pub publish --dry-run 2>&1 | tee "${publish_log}"
publish_status=${PIPESTATUS[0]}
set -e

if [[ ${publish_status} -ne 0 ]]; then
  echo "Publish dry run failed with exit code ${publish_status}." >&2
  exit "${publish_status}"
fi

if ! grep -Eq 'Package has 0 warnings[.!]?' "${publish_log}"; then
  echo "Publish dry run did not report Package has 0 warnings." >&2
  exit 1
fi

echo "Committed archive passed publish validation with zero warnings."
