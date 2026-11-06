#!/usr/bin/env bash
# Live view of the places a package Application can "exist", every few seconds, all via the Argo CD API:
#   REAL  - Application objects that exist (project=demo)
#   TREE  - Application nodes in demo-blueprint's resource tree (what the UI draws)
#   ASET  - names in the blueprint ApplicationSet's status.resources
#   CLICK - for each TREE node, the same GetResource call the UI makes when you click it
# A name in TREE/ASET but not REAL is printed as STALE; a CLICK that returns NotFound is the
# "Resource not found" error the UI shows.
# Usage: scripts/observe.sh [interval-seconds=3]
source "$(dirname "$0")/common.sh"
INTERVAL="${1:-3}"

while true; do
  FLAG="$(akc get "$CLUSTER_NAME" -o json 2>/dev/null \
          | jq -r '[paths(objects) as $p | select($p[-1]=="labels") | getpath($p)] | add // {} | .["demo-disabled"] // "?"')"
  REAL="$(api "applications?projects=demo" | jq -r '[.items[]?
           | select(.metadata.name|startswith("demo-package-"))
           | .metadata.name + (if .metadata.deletionTimestamp then "(deleting)" else "" end)] | sort | .[]' | tr '\n' ' ')"
  TREE="$(api "applications/demo-blueprint/resource-tree?appNamespace=argocd" \
          | jq -r '[.nodes[]? | select(.kind=="Application") | .name] | sort | .[]' 2>/dev/null | tr '\n' ' ')"
  ASET="$(api "applicationsets/demo-blueprint" | jq -r '[.status.resources[]?.name] | sort | .[]' 2>/dev/null | tr '\n' ' ')"
  CLICK=""
  for n in $TREE; do
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${ARGOCD_AUTH_TOKEN}" \
      "https://${ARGOCD_SERVER}/api/v1/applications/demo-blueprint/resource?appNamespace=argocd&namespace=argocd&resourceName=${n}&version=v1alpha1&kind=Application&group=argoproj.io")"
    CLICK="$CLICK $n=$code"
  done
  REALNAMES="$(echo "$REAL" | sed 's/(deleting)//g')"
  STALE=""
  for n in $TREE $ASET; do
    echo " $REALNAMES " | grep -q " $n " || STALE="$STALE $n"
  done
  STALE="$(echo "$STALE" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
  printf '%s disabled=%-5s\n  REAL:  %s\n  TREE:  %s\n  ASET:  %s\n  CLICK:%s\n' \
    "$(date -u +%H:%M:%S)" "$FLAG" "${REAL:--}" "${TREE:--}" "${ASET:--}" "${CLICK:- -}"
  [ -n "${STALE// /}" ] && printf '  \033[31mSTALE (visible but not found):%s\033[0m\n' "$STALE"
  sleep "$INTERVAL"
done
