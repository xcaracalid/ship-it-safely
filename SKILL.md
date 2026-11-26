---
name: ship-it-safely
description: Ship a code change safely with Flagsmith: wrap it in a flag, roll out gradually via multivariate weights, gate on health checks, and promote or roll back — with human approval before every production-affecting step. Use when asked to release, roll out, or roll back a change behind a feature flag.
license: MIT
compatibility: Requires the Flagsmith CLI v2.0.0+ and a Flagsmith Cloud (or self-hosted) account. Helper scripts need Python 3.10+.
metadata:
  author: yooghrn
  version: "1.0"
---

# Ship It Safely

Take ONE code change through the complete safe-ship job with the Flagsmith CLI:
recon → plan → create flag (disabled) → **approval stop** → gradual rollout in a
non-production environment → health gate → promote or auto-rollback → run report.

Flagsmith has no percentage-rollout switch for boolean flags. Gradual rollout is
done with **multivariate variant weights**: the flag carries a `control` variant
(the old behaviour) and a `new` variant (the change). Ramping = raising the
`new` variant's weight: 10 → 50 → 100. Rolling back = weight back to 0 and the
flag disabled. A segment-gated enable is the alternative when weights don't fit
(see "Alternative: segment gate").

## Safety rules (non-negotiable)

1. **Approval stop before anything production-affecting.** Creating a flag is
   safe (it is created disabled). Enabling, changing weights, or touching the
   production environment is NOT — present the plan summary (step 2) and wait
   for an explicit human "yes" before the first mutation, and again before any
   change in the production environment. Production confirmation must name the
   flag and the environment.
2. **Dry-run first.** Walk the whole job in the non-production environment
   (Development/Staging) before production is ever touched.
3. **Smallest step first.** First rollout step is weight 10 (never more).
   Steps: 10 → 50 → 100. Never skip a step; never jump straight to 100.
4. **Health gate after every step.** If the gate fails, roll back immediately
   (weight `new=0`, then disable) — do not ask first, do not retry the step.
   Rolling back is always safe and never needs approval.
5. **Journal everything.** Every command, its output size, and every state
   change goes into the run journal via `scripts/journal.py`. If it isn't in
   the journal, it didn't happen.
6. **Never print credentials.** Auth comes from `flagsmith login` or
   `FLAGSMITH_API_KEY` in the environment. Never echo keys into output, the
   journal, or the report.

## Token-efficiency rules (this is a judged axis — follow them)

- Always read with `--json` **and** a targeted `--jq` filter that returns only
  the fields the next decision needs (names, ids, enabled state, weights).
  Never ingest a raw `flag list` dump to "see what's there".
- One recon call per question. Batch: fetch the environment list once, the
  flag list once (filtered), the target flag once (filtered). Cache results in
  the journal instead of re-fetching.
- No exploratory loops: do not poll `evaluate` or re-list flags "to check".
  Verify a mutation with ONE filtered `flag get` after it.
- Keep command output out of the conversation when a summary suffices: pipe
  through `journal.py`, which records byte/token counts, and read back only
  the one-line status it prints.
- Record the run's token count in the report (step 7). The journal estimates
  tokens as output bytes / 4 for every CLI response consumed.

## Setup (once per repo)

```bash
flagsmith --version            # must be v2.x; install: curl -fsSL https://get.flagsmith.com | sh
flagsmith auth status          # or: export FLAGSMITH_API_KEY=... (never print it)
flagsmith init --project <project> --environment <non-prod-env-key>   # binds flagsmith.json
```

Configuration for a run (ask the user, or read from `ship-it-safely.json` in
the repo root if present):

- `flag` — name of the flag for this change (kebab/snake name, e.g. `new_checkout`).
- `description` — one line: what the change does.
- `health_check` — the command that must exit 0 for the rollout to continue
  (e.g. `./scripts/test.sh`, `npm test`, `gh run list --limit 1` checked by a
  wrapper). If none is configured, STOP and ask — a rollout without a health
  gate is out of spec for this skill.
- `prod_environment` — name/key of the production environment.

## The job

### Step 1 — Recon (read-only, token-lean)

```bash
flagsmith environment list --json --jq 'map({name, id})'
flagsmith flag list --json --jq 'map({name, enabled})'
flagsmith flag get <flag> --json --jq '{name, enabled, variants: [.variants[] | {key, weight}]}'   # if the flag already exists
flagsmith segment list --json --jq 'map({name, id})'   # only if the segment alternative is in play
```

Journal each call. From the results, fix: target project, non-prod environment,
whether the flag already exists, and its current state.

### Step 2 — Plan summary + approval stop

Present a short diff-like plan and STOP:

```
SHIP PLAN — flag: new_checkout
  project / env : Demo Project / Development (non-prod first)
  create        : flag "new_checkout", DISABLED, variants control=100 / new=0
  rollout       : new=10 → health gate → new=50 → health gate → new=100
  health check  : ./scripts/test.sh (must exit 0 after each step)
  rollback      : new=0 + disable flag (automatic on gate failure)
Approve? (yes/no)
```

No mutating command runs before a "yes".

### Step 3 — Create the flag (disabled, variants attached)

```bash
flagsmith feature create <flag> --value control --enabled=false --description "<description>"
flagsmith feature variant add <flag> --value new --key new --weight 0
flagsmith flag get <flag> --json --jq '{name, enabled, variants: [.variants[] | {key, weight}]}'
```

If the flag already exists, skip creation; verify its variants and state
instead, and say so in the plan. The flag must be DISABLED with `new` at
weight 0 before the rollout starts. Journal the verified state.

### Step 4 — Gradual rollout (non-prod), health gate after each step

For each weight in 10, 50, 100:

```bash
flagsmith flag update <flag> --weight new=<weight>
flagsmith flag enable <flag>          # only needed before the first step, if still disabled
flagsmith eval <flag> --test          # exits non-zero if the flag resolves disabled — sanity check
<health_check command>                # the user's configured check
```

- Gate passes → journal the state, continue to the next weight.
- Gate fails → go straight to step 6 (rollback). Do not continue, do not ask.

### Step 5 — Promote

At weight 100 with all gates green, the change is fully rolled out in the
non-prod environment. Report that state. Touching the **production**
environment is a separate, new approval stop: repeat steps 2–4 scoped to prod,
with the confirmation naming flag + production environment. Never carry a
non-prod approval over to prod.

### Step 6 — Rollback (automatic on failure, no approval needed)

```bash
flagsmith flag update <flag> --weight new=0
flagsmith flag disable <flag>
flagsmith flag get <flag> --json --jq '{name, enabled, variants: [.variants[] | {key, weight}]}'
```

Journal the incident: which step failed, the health check's exit code and last
output lines, and the verified rolled-back state.

### Step 7 — Run report

```bash
python3 scripts/report.py --journal <journal-file> --out report.md
```

The report lists every step and command, the rollout state after each step,
the health-gate results, the rollback (if any), and the **total token count**
for the run with its estimation method. End the job by showing the user the
report's summary block.

## Alternative: segment gate

When a change should reach a tester group before any percentage ramp: create a
segment (`flagsmith segment create <name> --rules @rule.json`), enable the flag
for that segment only, health-gate, then switch to the weight ramp for the
general rollout. The approval and rollback rules are identical.

## Journal & report helpers

```bash
# journal one CLI call (output piped in; prints a one-line status)
flagsmith flag list --json --jq 'map({name, enabled})' \
  | python3 scripts/journal.py add --journal runs/<run-id>.jsonl \
      --step recon --command "flagsmith flag list" --status ok

# free-form entries (approvals, gate results, incidents)
python3 scripts/journal.py add --journal runs/<run-id>.jsonl \
  --step approval --command "human approval" --status approved --note "plan v1 approved"

python3 scripts/journal.py total --journal runs/<run-id>.jsonl   # token total so far
python3 scripts/report.py --journal runs/<run-id>.jsonl --out report.md
```

## Demo mode (no account needed)

`demo/run-demo.sh` replays the whole job against a mock `flagsmith` stub
(`demo/flagsmith`) with canned state: one successful ship (10 → 50 → 100, all
gates green) and one forced health-gate failure that triggers the automatic
rollback. It produces a journal and a report exactly like a real run. Use it to
record the demo video and to measure the token-efficiency numbers.
