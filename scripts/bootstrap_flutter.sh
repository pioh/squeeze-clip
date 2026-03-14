#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_root="$root_dir/third_party/flutter"
cache_dir="$flutter_root/bin/cache"
version_file="$cache_dir/flutter.version.json"
legacy_version_file="$flutter_root/version"

mkdir -p "$cache_dir"

cat >"$version_file" <<'EOF'
{
  "frameworkVersion": "3.41.4",
  "channel": "[user-branch]",
  "repositoryUrl": "unknown source",
  "frameworkRevision": "ff37bef603469fb030f2b72995ab929ccfc227f0",
  "frameworkCommitDate": "2026-03-03 16:03:22 -0800",
  "engineRevision": "e4b8dca3f1b4ede4c30371002441c88c12187ed6",
  "engineCommitDate": "2026-03-03 18:24:54.000Z",
  "engineContentHash": "99578ad0355da00edb26301c874a3c250a5716f5",
  "engineBuildDate": "2026-03-04 01:41:09.880",
  "dartSdkVersion": "3.11.1",
  "devToolsVersion": "2.54.1",
  "flutterVersion": "3.41.4"
}
EOF

printf '3.41.4\n' >"$legacy_version_file"

"$flutter_root/bin/flutter" config --no-analytics --no-cli-animations
