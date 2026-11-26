#!/usr/bin/env python3
"""Append-only run journal for the ship-it-safely skill.

Each entry is one JSON object per line (JSONL). Entries record the step, the
command that ran, its status, and the size of the CLI output consumed so the
run's token cost can be totalled honestly.

Token estimation method: est_tokens = ceil(output_bytes / 4), the standard
rough heuristic for English/JSON text. The method is recorded in every entry
so reports can label it.

Usage:
  some-command --json | journal.py add --journal runs/x.jsonl \
      --step recon --command "flagsmith flag list" --status ok
  journal.py add --journal runs/x.jsonl --step approval \
      --command "human approval" --status approved --note "plan v1"
  journal.py total --journal runs/x.jsonl
"""
import argparse
import json
import math
import sys
from datetime import datetime, timezone

TOKEN_METHOD = "ceil(output_bytes/4)"


def est_tokens(nbytes: int) -> int:
    return math.ceil(nbytes / 4) if nbytes else 0


def cmd_add(args) -> int:
    data = sys.stdin.buffer.read() if not sys.stdin.isatty() else b""
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "step": args.step,
        "command": args.command,
        "status": args.status,
        "output_bytes": len(data),
        "est_tokens": est_tokens(len(data)),
        "token_method": TOKEN_METHOD,
    }
    if args.state:
        try:
            entry["state"] = json.loads(args.state)
        except json.JSONDecodeError:
            entry["state"] = args.state
    if args.note:
        entry["note"] = args.note
    with open(args.journal, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")
    # Echo the consumed output through so callers can still use it, but keep
    # the human-facing status on stderr to stay pipe-friendly.
    sys.stdout.buffer.write(data)
    print(
        f"[journal] {args.step}: {args.command} -> {args.status} "
        f"({entry['output_bytes']} bytes, ~{entry['est_tokens']} tokens)",
        file=sys.stderr,
    )
    return 0


def read_entries(path):
    entries = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                entries.append(json.loads(line))
    return entries


def cmd_total(args) -> int:
    entries = read_entries(args.journal)
    total_bytes = sum(e.get("output_bytes", 0) for e in entries)
    total_tokens = sum(e.get("est_tokens", 0) for e in entries)
    print(
        json.dumps(
            {
                "entries": len(entries),
                "output_bytes": total_bytes,
                "est_tokens": total_tokens,
                "token_method": TOKEN_METHOD,
            }
        )
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_add = sub.add_parser("add")
    p_add.add_argument("--journal", required=True)
    p_add.add_argument("--step", required=True)
    p_add.add_argument("--command", required=True)
    p_add.add_argument("--status", required=True)
    p_add.add_argument("--state", help="JSON string snapshot of flag state after this step")
    p_add.add_argument("--note")
    p_add.set_defaults(fn=cmd_add)

    p_total = sub.add_parser("total")
    p_total.add_argument("--journal", required=True)
    p_total.set_defaults(fn=cmd_total)

    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
