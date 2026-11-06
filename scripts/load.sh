#!/usr/bin/env bash
# Background load that mimics a busy control plane: a stream of refresh-annotation PATCHes
# (about 8/s by default). Each refresh sets the refresh annotation on an Application the blueprint
# AppSet owns, so the app controller AND the AppSet controller reconcile again and again.
# Usage: scripts/load.sh [seconds=300] [requests-per-second=8]
source "$(dirname "$0")/common.sh"
DURATION="${1:-300}"; RPS="${2:-8}"
END=$(( $(date +%s) + DURATION ))
echo "$(date -u +%H:%M:%S) load: ~${RPS} refresh/s for ${DURATION}s"
n=0
while [ "$(date +%s)" -lt "$END" ]; do
  apps="$(api "applications?projects=demo" | jq -r '.items[]?.metadata.name | select(startswith("demo-package-"))')"
  for a in $apps; do
    api "applications/${a}?refresh=normal&appNamespace=argocd" >/dev/null &
    n=$((n+1))
    sleep "$(awk -v r="$RPS" 'BEGIN{printf "%.3f", 1/r}')"
    [ "$(date +%s)" -ge "$END" ] && break
  done
  [ -z "$apps" ] && sleep 1
done
wait
echo "$(date -u +%H:%M:%S) load done: ${n} refreshes"
