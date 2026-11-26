#!/usr/bin/env python3
"""Generate a Markdown run report from a ship-it-safely journal (JSONL).

The report lists every step and command, the flag state recorded after each
step, health-gate outcomes, any rollback, and the run's total token count
with the estimation method used by journal.py.

Usage:
  report.py --journal runs/x.jsonl --out report.md
"""
import argparse
import json
import sys


def read_entries(path):
    entries = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                entries.append(json.loads(line))
    return entries


def fmt_state(state) -> str:
    if state is None:
        return "—"
    if isinstance(state, (dict, list)):
        return "`" + json.dumps(state) + "`"
    return str(state)


def build_report(entries, journal_path: str) -> str:
    total_bytes = sum(e.get("output_bytes", 0) for e in entries)
    total_tokens = sum(e.get("est_tokens", 0) for e in entries)
    method = entries[0].get("token_method", "unknown") if entries else "unknown"

    gates = [e for e in entries if e["step"] == "health-gate"]
    gates_failed = [e for e in gates if e["status"] != "pass"]
    rollbacks = [e for e in entries if e["step"] == "rollback"]
    approvals = [e for e in entries if e["step"] == "approval"]

    if rollbacks:
        outcome = "ROLLED BACK — health gate failed, flag returned to weight 0 and disabled."
    elif gates and not gates_failed:
        outcome = "SHIPPED — all rollout steps passed their health gates."
    else:
        outcome = "COMPLETED — see step log."

    lines = []
    lines.append("# Ship It Safely — run report")
    lines.append("")
    lines.append(f"- Journal: `{journal_path}`")
    lines.append(f"- Steps recorded: {len(entries)}")
    lines.append(f"- Approvals: {len(approvals)} | Health gates: {len(gates)} "
                 f"({len(gates) - len(gates_failed)} passed, {len(gates_failed)} failed) "
                 f"| Rollbacks: {len(rollbacks)}")
    lines.append(f"- **Outcome: {outcome}**")
    lines.append("")
    lines.append("## Token count")
    lines.append("")
    lines.append(f"- CLI output consumed: **{total_bytes} bytes**")
    lines.append(f"- **Estimated tokens: {total_tokens}** (method: {method} — "
                 "estimated from journalled CLI output sizes, not a provider billing figure)")
    lines.append("")
    lines.append("## Step log")
    lines.append("")
    lines.append("| # | Time (UTC) | Step | Command | Status | State after | Output |")
    lines.append("|---|------------|------|---------|--------|-------------|--------|")
    for i, e in enumerate(entries, 1):
        lines.append(
            f"| {i} | {e.get('ts', '')} | {e['step']} | `{e['command']}` | "
            f"{e['status']} | {fmt_state(e.get('state'))} | "
            f"{e.get('output_bytes', 0)} B (~{e.get('est_tokens', 0)} tok) |"
        )
    notes = [e for e in entries if e.get("note")]
    if notes:
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        for e in notes:
            lines.append(f"- [{e['step']}] {e['note']}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", required=True)
    parser.add_argument("--out", help="write report here (default: stdout)")
    args = parser.parse_args()
    entries = read_entries(args.journal)
    if not entries:
        print("journal is empty", file=sys.stderr)
        return 1
    report = build_report(entries, args.journal)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(report)
        print(f"report written to {args.out}")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
