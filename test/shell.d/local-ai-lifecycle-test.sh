#!/bin/bash
# Legacy container names survive upgrades; new deployments cannot collide across users.
set -euo pipefail
source "$(dirname "$0")/base-test.sh"
export OMARCHY_PATH=$ROOT
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE/deploy/test"
for owner in 1000 1001; do
  export PKEXEC_UID=$owner
  [[ $(engine test) == "omarchy-local-ai-$owner-test-engine" && $(gateway test) == "omarchy-local-ai-$owner-test-gateway" && $(network test) == "omarchy-local-ai-$owner-test" ]] || exit 1
done
unset PKEXEC_UID
echo 'ok - two users have different container and network names'
# A card can become allocated after the UI's check or while images download.
RECIPES=$TMP/recipes.json
echo '{"hardware":{"test":{"match":{"backend":"nvidia"}}},"gateway":{"image":"gateway"}}' >"$RECIPES"
recipe() { echo '{"hw":"test","cards":1,"image":"engine"}'; }
policy() { echo ok; }
nvidia_ready() { return 0; }
cdi_stale() { :; }
owned() { :; }
gpus() {
  if [[ -f $TMP/removed ]]; then
    echo '[{"key":"nvidia:0","hw":"test","held":true,"usedMiB":1}]'
  else
    echo '[{"key":"nvidia:0","hw":"test","held":false,"usedMiB":1}]'
  fi
}
remove() { touch "$TMP/removed"; }
docker() { case $1 in image) :;; info) echo NVIDIA;; *) touch "$TMP/launched"; return 99;; esac; }
if (phase_start test 12434 nvidia:0) >"$TMP/output" 2>&1; then exit 1; fi
grep -q 'nvidia:0 is in use by another program' "$TMP/output"
[[ ! -f $TMP/launched ]]
echo 'ok - launch rechecks allocations after downloads and before creating containers'

# A failed unshare must never expose a later model on this deployment's old URL.
echo '{"id":"test","port":12434,"shared":true}' >"$STATE/deploy/test/config.json"
echo '{"state":"ready"}' >"$STATE/deploy/test/status.json"
cmd_share() { return 1; }
elevate() { touch "$TMP/stopped"; }
if (cmd_stop test) >"$TMP/stop-output" 2>&1; then exit 1; fi
[[ -f $TMP/stopped && $(jq -r .port "$STATE/deploy/test/config.json") == 12434 ]]
cmd_share() { return 0; }
cmd_stop test
[[ ! -d $STATE/deploy/test ]]
echo 'ok - failed unsharing retains the stopped port until a successful retry'
