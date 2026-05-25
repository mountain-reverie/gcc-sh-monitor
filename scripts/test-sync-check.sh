#!/usr/bin/env bash
# Smoke test for sync-check.sh. Exercises both the no-change and changed paths
# using a stubbed `git ls-remote`.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fake upstream sha
fake_upstream="deadbeefcafebabe0000000000000000deadbeef"

# Stub ls-remote
cat > "$tmp/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "ls-remote" ]; then
  echo "$fake_upstream	refs/heads/master"
  exit 0
fi
exec /usr/bin/git "\$@"
EOF
chmod +x "$tmp/git"

# Case 1: state file matches upstream -> no change
mkdir -p "$tmp/state"
cat > "$tmp/state/last-tested.json" <<EOF
{"commit": "$fake_upstream", "detected_at": "2026-05-24T00:00:00Z", "status": "ok"}
EOF

PATH="$tmp:$PATH" STATE_FILE="$tmp/state/last-tested.json" \
  "$here/sync-check.sh" > "$tmp/out1" 2>&1
grep -q '^changed=false$' "$tmp/out1" || {
  echo "FAIL case 1: expected changed=false, got:"; cat "$tmp/out1"; exit 1;
}

# Case 2: state file differs -> change detected, file rewritten
cat > "$tmp/state/last-tested.json" <<EOF
{"commit": "0000000000000000000000000000000000000000", "detected_at": "2026-05-23T00:00:00Z", "status": "ok"}
EOF

PATH="$tmp:$PATH" STATE_FILE="$tmp/state/last-tested.json" \
  "$here/sync-check.sh" > "$tmp/out2" 2>&1
grep -q '^changed=true$' "$tmp/out2" || {
  echo "FAIL case 2: expected changed=true, got:"; cat "$tmp/out2"; exit 1;
}
new_commit=$(jq -r .commit "$tmp/state/last-tested.json")
[ "$new_commit" = "$fake_upstream" ] || {
  echo "FAIL case 2: state file not updated to $fake_upstream (got $new_commit)"; exit 1;
}

echo "PASS"
