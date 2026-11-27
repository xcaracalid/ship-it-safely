# Ship It Safely — a Flagsmith Agent Skill

An [Agent Skill](https://agentskills.io) that takes a coding agent through the
**complete** safe-ship job for one code change, using only the Flagsmith CLI:
wrap the change in a flag, roll it out gradually, gate every step on a health
check, and promote it — or roll it back automatically when a gate fails.

Built for **Toggle Wars (WeMakeDevs × Flagsmith), Track 04 — Flagsmith Agent
Skills**. The skill follows the standard Agent Skills format (`SKILL.md` with
YAML frontmatter + bundled scripts), so it loads in Claude Code and other
skills-compatible agents unchanged.

## Quickstart

**1. Install the skill** — copy this directory into your agent's skills folder:

```bash
cp -r ship-it-safely ~/.claude/skills/        # Claude Code
# or: cp -r ship-it-safely ~/.agents/skills/
```

**2. Try the demo (no Flagsmith account needed):**

```bash
bash demo/run-demo.sh
```

The demo replays the full workflow against a stateful mock of the Flagsmith
CLI: one change ships cleanly (10 → 50 → 100, all health gates green) and one
hits a forced gate failure at weight 10 and rolls back automatically. It
writes a run journal and a report with the demo's token count.

**3. For a real run** you need the Flagsmith CLI v2 (install via the official
script, Homebrew, or GitHub releases — not the legacy npm package), then:

```bash
flagsmith login    # OAuth — or set FLAGSMITH_API_KEY (see .env.example)
```

**How Flagsmith is used:** the skill drives the Flagsmith CLI for everything —
it creates a multivariate flag (`control`/`new` variants) around the change,
ramps the `new` variant's weight 10 → 50 → 100 with a health gate after every
step, and on a failed gate rolls back by setting `new=0` and disabling the
flag. Full detail in *The workflow* and *Safety model* below; the complete
install reference is in *Install the skill* further down.

## The workflow

```
            ┌──────────────────────────────────────────────────────────┐
            │                                                          │
            ▼                                                          │
 [1 RECON] ──► [2 PLAN + APPROVAL STOP] ──► [3 CREATE flag, disabled]  │
  --json +        human must say "yes"        variants control/new     │
  --jq reads      before any mutation                                  │
            ──► [4 ROLLOUT 10 → 50 → 100] ──► [5 PROMOTE]              │
                  weight ramp, non-prod        (prod = new approval)   │
                  + HEALTH GATE after                                  │
                    every step                                         │
                       │                                               │
                  gate fails ──► [6 ROLLBACK: new=0 + disable] ────────┘
                                  (automatic, no approval needed)
            ──► [7 RUN REPORT: steps, states, gates, token count]
```

Gradual rollout uses **multivariate variant weights** — the Flagsmith CLI has
no percentage switch for boolean flags, so the flag carries `control` (old
behaviour) and `new` (the change) variants, and ramping means raising the
`new` weight: 10 → 50 → 100. A segment-gated enable is supported as the
alternative first step.

## Safety model

- **Approval stops** before the first mutation and before anything touches
  the production environment (the prod confirmation must name flag + env).
  A non-prod approval never carries over to prod.
- **Dry-run first**: the whole job runs in a non-production environment
  before production is touched.
- **Smallest step first**: first ramp is weight 10, steps are 10 → 50 → 100,
  never a jump to 100.
- **Health gate after every step**, using a check command the user configures
  (tests, CI status, smoke script — anything that exits non-zero on trouble).
  No configured gate = the skill refuses to roll out.
- **Automatic rollback**: on any gate failure the skill sets `new=0` and
  disables the flag immediately — no approval needed, because rolling back is
  always the safe direction — then verifies and journals the rolled-back state.
- **Everything is journalled** (append-only JSONL): every command, output
  size, state snapshot, approval, gate result, and incident.
- **Credentials never printed**: auth via `flagsmith login` or
  `FLAGSMITH_API_KEY` in the environment/`.env` only.

## Token efficiency (a judged axis — measured, not claimed)

The skill reads Flagsmith state only through `--json` + targeted `--jq`
filters, fetches each list once, verifies mutations with a single filtered
`flag get`, and routes CLI output through the journal helper so only one-line
statuses enter the conversation.

Measured on the bundled demo run (`demo/run-demo.sh`, mock CLI, 26 journalled
steps covering a full ship **and** a full rollback):

| Measure | Value |
|---|---|
| Whole demo run — CLI output consumed | **930 bytes ≈ 245 tokens** |
| Recon: raw `flag list --json` dump | 6,363 bytes |
| Recon: the `--jq`-filtered read actually consumed | **238 bytes (−96%)** |

Token counts are estimated as `ceil(output_bytes / 4)` from the journalled
output sizes — the method is recorded in the journal and labelled in every
report; it is an estimate of CLI output consumed, not a provider billing
figure.

## Install the skill

Copy or symlink this directory into your agent's skills folder, e.g.:

```bash
cp -r ship-it-safely ~/.claude/skills/        # Claude Code
# or: cp -r ship-it-safely ~/.agents/skills/
```

Then ask your agent to "ship <change> safely with Flagsmith" — or invoke the
workflow from `SKILL.md` directly.

Prerequisites for real runs:

```bash
curl -fsSL https://get.flagsmith.com | sh     # Flagsmith CLI v2 (or brew install Flagsmith/tap/flagsmith)
flagsmith login                               # OAuth — or set FLAGSMITH_API_KEY (see .env.example)
flagsmith init --project <project> --environment <non-prod-env-key>
```

> Note: `npm install -g @flagsmith/cli` installs the **legacy** npm CLI, not
> v2 — the current docs steer installs to the script/Homebrew/releases.

## Run the demo (no account needed)

```bash
bash demo/run-demo.sh
```

This replays the whole job against `demo/flagsmith`, a stateful mock of the
CLI subset the skill uses, with canned project data:

- **Scenario A** — `new_checkout` ships cleanly: 10 → 50 → 100, all health
  gates green.
- **Scenario B** — `risky_pricing` hits a **forced health-gate failure** at
  weight 10 and the automatic rollback fires; the final verified state is
  `enabled: false, new weight: 0`.

Outputs: `demo/runs/demo-journal.jsonl` (the append-only run journal) and
`demo/demo-report.md` (steps, states, gate results, token count). Approvals
in the demo are auto-granted and journalled as demo auto-approvals — a real
run stops and waits for a human at exactly those points.

## What changes with real credentials

Nothing in the workflow. With `flagsmith login` done (or `FLAGSMITH_API_KEY`
set) and `flagsmith init` binding the repo to a project + non-prod
environment, the same commands run against Flagsmith Cloud: recon reads real
state, the approval stop waits for a real human, the health gate runs your
real check command, and `scripts/report.py` produces the same report from the
real journal. The mock exists only so the loop can be demonstrated and
recorded before an account is involved.

## Layout

```
ship-it-safely/
├── SKILL.md            # the skill: workflow, safety rules, token rules
├── scripts/
│   ├── journal.py      # append-only JSONL run journal + token counter
│   └── report.py       # journal -> Markdown run report
├── demo/
│   ├── flagsmith       # mock CLI stub (canned, stateful)
│   ├── checks/         # pass.sh / fail.sh demo health gates
│   ├── run-demo.sh     # full replay: ship + forced-failure rollback
│   └── demo-report.md  # generated report from the demo run
├── .env.example        # credential template (never commit a real .env)
└── README.md
```

## Licence

MIT.
