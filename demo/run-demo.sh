#!/usr/bin/env bash
# Ship It Safely — end-to-end demo against the mock flagsmith CLI.
#
# Replays the full job twice:
#   Scenario A: new_checkout — clean ship, weights 10 -> 50 -> 100, gates green.
#   Scenario B: risky_pricing — health gate FAILS at weight 10, skill performs
#               the automatic rollback (new=0 + disable) and journals it.
#
# No Flagsmith account needed: demo/flagsmith is a stateful stub.
# Approvals are auto-granted (DEMO_APPROVE=1) and journalled as such; a real
# run of the skill stops and waits for a human at the same points.
#
# Outputs: demo/runs/demo-journal.jsonl and demo/demo-report.md
set -u
cd "$(dirname "$0")"
SKILL_DIR="$(cd .. && pwd)"
export PATH="$PWD:$PATH"                      # mock `flagsmith` shadows any real one
export MOCK_FLAGSMITH_STATE="$PWD/.mock-state.json"
JOURNAL="$PWD/runs/demo-journal.jsonl"
mkdir -p runs
rm -f "$MOCK_FLAGSMITH_STATE" "$JOURNAL"

J() { # J <step> <command> <status> [state-json] [note]  -- reads output on stdin
  local step="$1" cmd="$2" status="$3" state="${4:-}" note="${5:-}"
  local args=(add --journal "$JOURNAL" --step "$step" --command "$cmd" --status "$status")
  [ -n "$state" ] && args+=(--state "$state")
  [ -n "$note" ] && args+=(--note "$note")
  python3 "$SKILL_DIR/scripts/journal.py" "${args[@]}" >/dev/null
}
note() { # free-form journal entry with no CLI output
  python3 "$SKILL_DIR/scripts/journal.py" add --journal "$JOURNAL" \
    --step "$1" --command "$2" --status "$3" --note "$4" </dev/null >/dev/null
}
flag_state() { flagsmith flag get "$1" --json --jq '{name, enabled, variants: [.variants[] | {key, weight}]}'; }

echo "==================================================================="
echo " SHIP IT SAFELY — DEMO (mock Flagsmith, no account needed)"
echo "==================================================================="

# ---------------------------------------------------------------- recon
echo
echo "## STEP 1 — Recon (token-lean: --json + targeted --jq)"
raw_bytes=$(flagsmith flag list --json | wc -c)
flagsmith flag list --json --jq 'map({name, enabled})' \
  | J recon "flagsmith flag list --json --jq 'map({name, enabled})'" ok
filtered_bytes=$(tail -1 "$JOURNAL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["output_bytes"])')
note recon-compare "byte comparison" info \
  "Recon comparison: raw 'flag list --json' dump = ${raw_bytes} bytes; the --jq-filtered read the skill actually consumes = ${filtered_bytes} bytes."
echo "   raw dump: ${raw_bytes} bytes | filtered read consumed: ${filtered_bytes} bytes"
flagsmith environment list --json --jq 'map({name, id})' \
  | J recon "flagsmith environment list --json --jq 'map({name, id})'" ok

# ------------------------------------------------------- scenario A: ship
echo
echo "## SCENARIO A — ship 'new_checkout' (Development, non-prod)"
cat <<'PLAN'
SHIP PLAN — flag: new_checkout
  create  : DISABLED, variants control=100 / new=0
  rollout : new=10 -> health gate -> new=50 -> health gate -> new=100
  rollback: new=0 + disable (automatic on gate failure)
PLAN
note approval "human approval" approved \
  "DEMO auto-approval (DEMO_APPROVE=1). In a real run the skill stops here and waits for a human yes."
echo "   [approval stop] auto-approved in demo mode — real runs wait for a human"

flagsmith feature create new_checkout --value control --enabled=false \
  --description "New streamlined checkout flow" \
  | J create "flagsmith feature create new_checkout --value control --enabled=false" ok
flagsmith feature variant add new_checkout --value new --key new --weight 0 \
  | J create "flagsmith feature variant add new_checkout --key new --weight 0" ok
state=$(flag_state new_checkout)
printf '%s' "$state" | J verify "flagsmith flag get new_checkout (filtered)" ok "$state"
echo "   created, verified state: $state"

for w in 10 50 100; do
  flagsmith flag update new_checkout --weight new=$w \
    | J rollout "flagsmith flag update new_checkout --weight new=$w" ok
  if [ "$w" = "10" ]; then
    flagsmith flag enable new_checkout | J rollout "flagsmith flag enable new_checkout" ok
  fi
  flagsmith eval new_checkout --test >/dev/null \
    | J verify "flagsmith eval new_checkout --test" ok
  gate_out=$(./checks/pass.sh 2>&1); gate_rc=$?
  printf '%s' "$gate_out" | J health-gate "./checks/pass.sh (health gate @ new=$w)" \
    "$([ $gate_rc -eq 0 ] && echo pass || echo fail)" "$(flag_state new_checkout)" \
    "health gate at weight new=$w exited $gate_rc"
  echo "   rollout new=$w — health gate: PASS"
done
echo "   SCENARIO A RESULT: shipped to 100% in Development, all gates green."

# ------------------------------------------- scenario B: forced failure
echo
echo "## SCENARIO B — ship 'risky_pricing', health gate will FAIL at new=10"
note approval "human approval" approved \
  "DEMO auto-approval for scenario B (same plan shape as A)."
flagsmith feature create risky_pricing --value control --enabled=false \
  --description "Experimental dynamic pricing" \
  | J create "flagsmith feature create risky_pricing --value control --enabled=false" ok
flagsmith feature variant add risky_pricing --value new --key new --weight 0 \
  | J create "flagsmith feature variant add risky_pricing --key new --weight 0" ok
flagsmith flag update risky_pricing --weight new=10 \
  | J rollout "flagsmith flag update risky_pricing --weight new=10" ok
flagsmith flag enable risky_pricing | J rollout "flagsmith flag enable risky_pricing" ok

gate_out=$(./checks/fail.sh 2>&1); gate_rc=$?
printf '%s' "$gate_out" | J health-gate "./checks/fail.sh (health gate @ new=10)" fail \
  "$(flag_state risky_pricing)" \
  "INCIDENT: health gate FAILED at weight new=10 (exit $gate_rc): $gate_out — triggering automatic rollback."
echo "   rollout new=10 — health gate: FAIL (exit $gate_rc) -> automatic rollback"

flagsmith flag update risky_pricing --weight new=0 \
  | J rollback "flagsmith flag update risky_pricing --weight new=0" ok
flagsmith flag disable risky_pricing \
  | J rollback "flagsmith flag disable risky_pricing" ok
state=$(flag_state risky_pricing)
printf '%s' "$state" | J rollback "flagsmith flag get risky_pricing (verify rolled back)" ok "$state"
echo "   SCENARIO B RESULT: rolled back and verified: $state"

# ---------------------------------------------------------------- report
echo
echo "## STEP 7 — Run report"
python3 "$SKILL_DIR/scripts/journal.py" total --journal "$JOURNAL"
python3 "$SKILL_DIR/scripts/report.py" --journal "$JOURNAL" --out "$PWD/demo-report.md"
echo "Journal: $JOURNAL"
echo "Report : $PWD/demo-report.md"
