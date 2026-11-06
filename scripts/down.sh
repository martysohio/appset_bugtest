#!/usr/bin/env bash
# Remove the demo from the Argo CD instance. Touches only demo objects:
#   ApplicationSet demo-spoke (cascades: demo-blueprint -> AppSet demo-blueprint -> demo-package-*),
#   AppProject demo, and the demo-* labels on the cluster.
source "$(dirname "$0")/common.sh"

acd appset delete demo-spoke -y || true
echo "waiting for demo apps to be deleted..."
for _ in $(seq 1 60); do
  left="$(api "applications?projects=demo" | jq '[.items[]?] | length')"
  [ "$left" = "0" ] && break
  sleep 5
done
acd proj delete demo || true
set_demo_labels   # drops demo-tenant / demo-disabled, keeps everything else
echo "Done. The demo-workloads namespace on $CLUSTER_NAME is left in place (CreateNamespace does not prune it);"
echo "delete it from a kube context for $CLUSTER_NAME if you want it gone."
