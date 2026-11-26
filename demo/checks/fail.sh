#!/bin/sh
# Demo health check that FAILS (simulates a regression caught by the gate).
echo "health-check: FAILED — 3 tests failing in checkout/pricing suite (simulated regression)"
exit 1
