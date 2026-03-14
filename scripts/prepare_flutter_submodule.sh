#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_root="${1:-$root_dir/third_party/flutter}"
flutter_tag="${2:-3.41.4}"

if [ ! -d "$flutter_root/.git" ] && [ ! -f "$flutter_root/.git" ]; then
  echo "Flutter submodule is missing at: $flutter_root" >&2
  exit 1
fi

flutter_head="$(git -C "$flutter_root" rev-parse HEAD)"

# Flutter CLI gets braindead in detached submodule checkouts and reports
# 0.0.0-unknown. Pull the matching release tag and pin the current commit onto
# a local stable branch instead of faking version files like a circus act.
git -C "$flutter_root" fetch --depth=1 origin "refs/tags/$flutter_tag:refs/tags/$flutter_tag"
git -C "$flutter_root" checkout -B stable "$flutter_head"
"$flutter_root/bin/flutter" config --no-analytics --no-cli-animations
