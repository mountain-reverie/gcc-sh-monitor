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

# Case 3: ls-remote emits multiple suffix-matching refs -> must pick refs/heads/$BRANCH only
real_master="1111111111111111111111111111111111111111"
noisy_branch="2222222222222222222222222222222222222222"

cat > "$tmp/git" <<EOF
#!/usr/bin/env bash
# This stub returns TWO matching refs to simulate the gcc-mirror situation
# where 'master' suffix-matches both refs/heads/master and refs/heads/devel/rust/master.
# sync-check.sh must request the fully-qualified ref to disambiguate.
if [ "\$1" = "ls-remote" ]; then
  # When called with the fully-qualified ref, return only master.
  # When called with bare "master", return both (the bug we're guarding against).
  if [ "\$3" = "refs/heads/master" ]; then
    echo "$real_master	refs/heads/master"
  else
    echo "$noisy_branch	refs/heads/devel/rust/master"
    echo "$real_master	refs/heads/master"
  fi
  exit 0
fi
exec /usr/bin/git "\$@"
EOF
chmod +x "$tmp/git"

# Reset state to differ from real_master so we exercise the changed=true path.
cat > "$tmp/state/last-tested.json" <<EOF
{"commit": "0000000000000000000000000000000000000000", "detected_at": "2026-05-23T00:00:00Z", "status": "ok"}
EOF

PATH="$tmp:$PATH" STATE_FILE="$tmp/state/last-tested.json" \
  "$here/sync-check.sh" > "$tmp/out3" 2>&1
grep -q "^commit=$real_master$" "$tmp/out3" || {
  echo "FAIL case 3: expected commit=$real_master, got:"; cat "$tmp/out3"; exit 1;
}
grep -q '^changed=true$' "$tmp/out3" || {
  echo "FAIL case 3: expected changed=true, got:"; cat "$tmp/out3"; exit 1;
}
new_commit=$(jq -r .commit "$tmp/state/last-tested.json")
[ "$new_commit" = "$real_master" ] || {
  echo "FAIL case 3: state file not updated to $real_master (got $new_commit)"; exit 1;
}

echo "PASS"
