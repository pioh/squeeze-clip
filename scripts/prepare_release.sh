#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/prepare_release.sh <version>" >&2
  echo "Example: scripts/prepare_release.sh 0.1.1" >&2
  exit 1
fi

version="$1"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like x.y.z" >&2
  exit 1
fi

build_number="$(git rev-list --count HEAD)"
pubspec_file="pubspec.yaml"

python - <<'PY' "$pubspec_file" "$version" "$build_number"
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
version = sys.argv[2]
build_number = sys.argv[3]
text = path.read_text()
text, count = re.subn(r'^version:\s+.+$', f'version: {version}+{build_number}', text, flags=re.M)
if count != 1:
    raise SystemExit('Could not update pubspec version')
path.write_text(text)
PY

echo "Updated ${pubspec_file} to ${version}+${build_number}"
echo "Next:"
echo "  1. update CHANGELOG.md"
echo "  2. git commit -am 'Release ${version}'"
echo "  3. git tag -a v${version} -m 'Release v${version}'"
echo "  4. git push origin main --follow-tags"
