#!/bin/zsh
# One-time golden-image setup for the VM eval lane (KIS-182).
#
# Builds "suniye-cu-golden": a macOS guest with SSH key auth and the eval
# runner installed, its Accessibility + Screen Recording permissions granted
# ONCE through the guest's UI. Per-sweep clones are APFS copy-on-write, so the
# golden image is the only real disk cost and every clone inherits the grant.
#
# Why a manual grant: the Cirrus base images ship with SIP enabled, which makes
# the system TCC database read-only — sqlite3 injection fails with "attempt to
# write a readonly database". A grant through the UI is the SIP-legal path, and
# doing it once in the golden image means clones never need it again.
#
# Environment:
#   SUNIYE_CU_VM_IMAGE   base image (default: ghcr.io/cirruslabs/macos-tahoe-vanilla:latest)
#   TART                 tart binary (default: tart on PATH, then ~/.local/bin/tart)

set -euo pipefail
cd "$(dirname "$0")/.."

TART="${TART:-$(command -v tart || echo "$HOME/.local/bin/tart")}"
IMAGE="${SUNIYE_CU_VM_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-vanilla:latest}"
GOLDEN="suniye-cu-golden"
SSH_KEY="$HOME/.ssh/suniye-cu-eval"

run_ssh() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes admin@"$IP" "$@"
}

wait_for_ssh() {
  IP=""
  for _ in {1..90}; do
    IP="$("$TART" ip "$GOLDEN" 2>/dev/null || true)"
    [[ -n "$IP" ]] && nc -z "$IP" 22 2>/dev/null && return 0
    sleep 5
  done
  echo "ERROR: guest never became reachable" >&2
  return 1
}

# --- Build the golden image if absent, otherwise reuse it -------------------
if ! "$TART" list | awk '{print $2}' | grep -qx "$GOLDEN"; then
  [[ -f "$SSH_KEY" ]] || ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "suniye-cu-eval"
  echo "Pulling base image (tens of GB on first run)..."
  "$TART" pull "$IMAGE"
  "$TART" clone "$IMAGE" "$GOLDEN"

  echo "Booting golden image to install the SSH key..."
  "$TART" run --no-graphics "$GOLDEN" &
  wait_for_ssh
  expect <<EXPECT
set timeout 90
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP \
  "mkdir -p ~/.ssh && echo '$(cat "$SSH_KEY.pub")' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
expect {
  "Password:" { send "admin\r"; exp_continue }
  eof
}
EXPECT
  run_ssh 'sudo shutdown -h now' || true
  sleep 10
fi

# --- Install the runner into the golden image -------------------------------
echo "Building the eval runner..."
xcodegen generate >/dev/null
xcodebuild -project Suniye.xcodeproj -scheme SuniyeEvalRunner \
  -destination 'platform=macOS' -derivedDataPath .derivedData -configuration Release build >/dev/null
RUNNER=".derivedData/Build/Products/Release/SuniyeEvalRunner.app"
[[ -d "$RUNNER" ]] || { echo "ERROR: runner build missing at $RUNNER" >&2; exit 1; }

echo "Booting the golden image (a window will open for the one-time grant)..."
"$TART" run "$GOLDEN" &
wait_for_ssh
run_ssh 'rm -rf ~/Applications/SuniyeEvalRunner.app && mkdir -p ~/Applications ~/suniye-eval'
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -r "$RUNNER" admin@"$IP":'~/Applications/SuniyeEvalRunner.app'

cat <<INSTRUCTIONS

============================================================================
ONE-TIME MANUAL GRANT (in the VM window that just opened)

  1. Open System Settings > Privacy & Security.
  2. Under Accessibility, add ~/Applications/SuniyeEvalRunner.app and enable it.
  3. Under Screen Recording, add the same app and enable it.

The window is a real macOS desktop; drag the app in from ~/Applications or use
the + picker. This grant persists into every disposable clone.

When done, press Return here to snapshot the golden image and shut it down.
============================================================================
INSTRUCTIONS
read -r _

run_ssh 'sudo shutdown -h now' || true
echo "Golden image '$GOLDEN' ready. Run sweeps with scripts/run_computer_use_evals_vm.sh"
