#!/usr/bin/env bash
# Flip the tenant's disabled switch: the demo-disabled label on the managed cluster, which the
# spoke AppSet's cluster generator passes into demo-blueprint's Helm values.
# true  -> blueprint AppSet generates 0 -> every demo-package-* Application is deleted
# false -> packages are recreated
# Usage: scripts/flip.sh true|false
source "$(dirname "$0")/common.sh"
VAL="${1:?usage: flip.sh true|false}"
set_demo_labels demo-tenant=demo "demo-disabled=${VAL}"
echo "$(date -u +%H:%M:%S) disabled=${VAL}"
