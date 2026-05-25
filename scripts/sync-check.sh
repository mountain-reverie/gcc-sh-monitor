#!/usr/bin/env bash
# Detects whether upstream gcc-mirror/gcc HEAD has changed since the last
# recorded commit in $STATE_FILE. Emits two lines on stdout suitable for
# $GITHUB_OUTPUT:
#   changed=true|false
#   commit=<upstream-sha>
# When changed=true, also rewrites $STATE_FILE in place with the new sha.
#
# Environment:
#   STATE_FILE  path to last-tested.json (default: state/last-tested.json)
#   UPSTREAM    upstream git URL (default: https://github.com/gcc-mirror/gcc.git)
#   BRANCH      upstream branch (default: master)

set -euo pipefail

STATE_FILE="${STATE_FILE:-state/last-tested.json}"
UPSTREAM="${UPSTREAM:-https://github.com/gcc-mirror/gcc.git}"
BRANCH="${BRANCH:-master}"

upstream_sha=$(git ls-remote "$UPSTREAM" "$BRANCH" | cut -f1)
if [ -z "$upstream_sha" ]; then
  echo "sync-check: empty ls-remote result for $UPSTREAM $BRANCH" >&2
  exit 1
fi

current_sha=$(jq -r .commit "$STATE_FILE")

echo "commit=$upstream_sha"

if [ "$upstream_sha" = "$current_sha" ]; then
  echo "changed=false"
  exit 0
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp="${STATE_FILE}.tmp"
jq --arg c "$upstream_sha" --arg t "$now" \
   '.commit = $c | .detected_at = $t | .status = "pending"' \
   "$STATE_FILE" > "$tmp"
mv "$tmp" "$STATE_FILE"

echo "changed=true"
