#!/bin/zsh
# One-time golden-image setup for the VM eval lane (KIS-182).
#
# Builds "suniye-cu-golden": a macOS guest with SSH key auth, auto-login, and
# TCC pre-granted to the eval runner's bundle id. Per-sweep clones are APFS
# copy-on-write, so the golden image is the only real disk cost (~40 GB).
#
# The base image download is tens of GB; run `tart pull` ahead of time if you
# want progress in your own terminal. Cirrus images ship user admin/admin,
# passwordless sudo, auto-login, and SIP disabled — the last is what makes the
# NULL-csreq TCC grant below legal, and that grant matches by bundle id alone,
# so rebuilt (re-signed) runner binaries keep their permissions.
#
# Environment:
#   SUNIYE_CU_VM_IMAGE   base image (default: ghcr.io/cirruslabs/macos-tahoe-vanilla:latest)
#   TART                 tart binary (default: tart on PATH, then ~/.local/bin/tart)

set -euo pipefail

TART="${TART:-$(command -v tart || echo "$HOME/.local/bin/tart")}"
IMAGE="${SUNIYE_CU_VM_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-vanilla:latest}"
GOLDEN="suniye-cu-golden"
SSH_KEY="$HOME/.ssh/suniye-cu-eval"

if "$TART" list | awk '{print $2}' | grep -qx "$GOLDEN"; then
  echo "Golden image '$GOLDEN' already exists; delete it with '$TART delete $GOLDEN' to rebuild."
  exit 0
fi

[[ -f "$SSH_KEY" ]] || ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "suniye-cu-eval"

echo "Pulling base image (tens of GB on first run)..."
"$TART" pull "$IMAGE"
"$TART" clone "$IMAGE" "$GOLDEN"

echo "Booting golden image headless..."
"$TART" run --no-graphics "$GOLDEN" &
VM_PID=$!
trap '"$TART" stop "$GOLDEN" 2>/dev/null || kill $VM_PID 2>/dev/null || true' EXIT

IP=""
for _ in {1..60}; do
  IP="$("$TART" ip "$GOLDEN" 2>/dev/null || true)"
  [[ -n "$IP" ]] && nc -z "$IP" 22 2>/dev/null && break
  sleep 5
done
[[ -n "$IP" ]] || { echo "ERROR: guest never became reachable" >&2; exit 1; }
echo "Guest at $IP; installing SSH key..."

# First contact uses password auth (admin/admin) via expect, installing our
# key so everything after is non-interactive.
expect <<EXPECT
set timeout 60
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP \
  "mkdir -p ~/.ssh && echo '$(cat "$SSH_KEY.pub")' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
expect {
  "Password:" { send "admin\r"; exp_continue }
  eof
}
EXPECT

run_ssh() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "admin@$IP" "$@"
}

echo "Pre-granting Accessibility + Screen Recording to dev.suniye.evalrunner..."
run_ssh 'sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags) \
   VALUES (\"kTCCServiceScreenCapture\", \"dev.suniye.evalrunner\", 0, 2, 4, 1, 0);" && \
  sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags) \
   VALUES (\"kTCCServiceAccessibility\", \"dev.suniye.evalrunner\", 0, 2, 4, 1, 0), \
          (\"kTCCServiceAppleEvents\", \"dev.suniye.evalrunner\", 0, 2, 4, 1, 0);"'

run_ssh 'mkdir -p ~/suniye-eval'
echo "Shutting down golden image..."
run_ssh 'sudo shutdown -h now' || true
wait $VM_PID 2>/dev/null || true
trap - EXIT
echo "Golden image '$GOLDEN' ready. Run sweeps with scripts/run_computer_use_evals_vm.sh"
