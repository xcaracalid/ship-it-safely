# Ship It Safely — run report

- Journal: `/home/hatch/workspace/toggle-wars/ship-it-safely/demo/runs/demo-journal.jsonl`
- Steps recorded: 26
- Approvals: 2 | Health gates: 4 (3 passed, 1 failed) | Rollbacks: 3
- **Outcome: ROLLED BACK — health gate failed, flag returned to weight 0 and disabled.**

## Token count

- CLI output consumed: **930 bytes**
- **Estimated tokens: 245** (method: ceil(output_bytes/4) — estimated from journalled CLI output sizes, not a provider billing figure)

## Step log

| # | Time (UTC) | Step | Command | Status | State after | Output |
|---|------------|------|---------|--------|-------------|--------|
| 1 | 2026-11-26T08:46:01+00:00 | recon | `flagsmith flag list --json --jq 'map({name, enabled})'` | ok | — | 238 B (~60 tok) |
| 2 | 2026-11-26T08:46:01+00:00 | recon-compare | `byte comparison` | info | — | 0 B (~0 tok) |
| 3 | 2026-11-26T08:46:02+00:00 | recon | `flagsmith environment list --json --jq 'map({name, id})'` | ok | — | 65 B (~17 tok) |
| 4 | 2026-11-26T08:46:02+00:00 | approval | `human approval` | approved | — | 0 B (~0 tok) |
| 5 | 2026-11-26T08:46:02+00:00 | create | `flagsmith feature create new_checkout --value control --enabled=false` | ok | — | 13 B (~4 tok) |
| 6 | 2026-11-26T08:46:02+00:00 | create | `flagsmith feature variant add new_checkout --key new --weight 0` | ok | — | 13 B (~4 tok) |
| 7 | 2026-11-26T08:46:02+00:00 | verify | `flagsmith flag get new_checkout (filtered)` | ok | `{"name": "new_checkout", "enabled": false, "variants": [{"key": "control", "weight": 100}, {"key": "new", "weight": 0}]}` | 108 B (~27 tok) |
| 8 | 2026-11-26T08:46:02+00:00 | rollout | `flagsmith flag update new_checkout --weight new=10` | ok | — | 13 B (~4 tok) |
| 9 | 2026-11-26T08:46:02+00:00 | rollout | `flagsmith flag enable new_checkout` | ok | — | 13 B (~4 tok) |
| 10 | 2026-11-26T08:46:02+00:00 | verify | `flagsmith eval new_checkout --test` | ok | — | 0 B (~0 tok) |
| 11 | 2026-11-26T08:46:02+00:00 | health-gate | `./checks/pass.sh (health gate @ new=10)` | pass | `{"name": "new_checkout", "enabled": true, "variants": [{"key": "control", "weight": 90}, {"key": "new", "weight": 10}]}` | 53 B (~14 tok) |
| 12 | 2026-11-26T08:46:02+00:00 | rollout | `flagsmith flag update new_checkout --weight new=50` | ok | — | 13 B (~4 tok) |
| 13 | 2026-11-26T08:46:02+00:00 | verify | `flagsmith eval new_checkout --test` | ok | — | 0 B (~0 tok) |
| 14 | 2026-11-26T08:46:02+00:00 | health-gate | `./checks/pass.sh (health gate @ new=50)` | pass | `{"name": "new_checkout", "enabled": true, "variants": [{"key": "control", "weight": 50}, {"key": "new", "weight": 50}]}` | 53 B (~14 tok) |
| 15 | 2026-11-26T08:46:02+00:00 | rollout | `flagsmith flag update new_checkout --weight new=100` | ok | — | 13 B (~4 tok) |
| 16 | 2026-11-26T08:46:02+00:00 | verify | `flagsmith eval new_checkout --test` | ok | — | 0 B (~0 tok) |
| 17 | 2026-11-26T08:46:03+00:00 | health-gate | `./checks/pass.sh (health gate @ new=100)` | pass | `{"name": "new_checkout", "enabled": true, "variants": [{"key": "control", "weight": 0}, {"key": "new", "weight": 100}]}` | 53 B (~14 tok) |
| 18 | 2026-11-26T08:46:03+00:00 | approval | `human approval` | approved | — | 0 B (~0 tok) |
| 19 | 2026-11-26T08:46:03+00:00 | create | `flagsmith feature create risky_pricing --value control --enabled=false` | ok | — | 14 B (~4 tok) |
| 20 | 2026-11-26T08:46:03+00:00 | create | `flagsmith feature variant add risky_pricing --key new --weight 0` | ok | — | 14 B (~4 tok) |
| 21 | 2026-11-26T08:46:03+00:00 | rollout | `flagsmith flag update risky_pricing --weight new=10` | ok | — | 14 B (~4 tok) |
| 22 | 2026-11-26T08:46:03+00:00 | rollout | `flagsmith flag enable risky_pricing` | ok | — | 14 B (~4 tok) |
| 23 | 2026-11-26T08:46:03+00:00 | health-gate | `./checks/fail.sh (health gate @ new=10)` | fail | `{"name": "risky_pricing", "enabled": true, "variants": [{"key": "control", "weight": 90}, {"key": "new", "weight": 10}]}` | 89 B (~23 tok) |
| 24 | 2026-11-26T08:46:03+00:00 | rollback | `flagsmith flag update risky_pricing --weight new=0` | ok | — | 14 B (~4 tok) |
| 25 | 2026-11-26T08:46:03+00:00 | rollback | `flagsmith flag disable risky_pricing` | ok | — | 14 B (~4 tok) |
| 26 | 2026-11-26T08:46:03+00:00 | rollback | `flagsmith flag get risky_pricing (verify rolled back)` | ok | `{"name": "risky_pricing", "enabled": false, "variants": [{"key": "control", "weight": 100}, {"key": "new", "weight": 0}]}` | 109 B (~28 tok) |

## Notes

- [recon-compare] Recon comparison: raw 'flag list --json' dump = 6362 bytes; the --jq-filtered read the skill actually consumes = 238 bytes.
- [approval] DEMO auto-approval (DEMO_APPROVE=1). In a real run the skill stops here and waits for a human yes.
- [health-gate] health gate at weight new=10 exited 0
- [health-gate] health gate at weight new=50 exited 0
- [health-gate] health gate at weight new=100 exited 0
- [approval] DEMO auto-approval for scenario B (same plan shape as A).
- [health-gate] INCIDENT: health gate FAILED at weight new=10 (exit 1): health-check: FAILED — 3 tests failing in checkout/pricing suite (simulated regression) — triggering automatic rollback.
