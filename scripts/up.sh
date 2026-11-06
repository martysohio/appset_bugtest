#!/usr/bin/env bash
# Bootstrap the spoke -> blueprint -> package chain on a managed Argo CD instance.
# Prereqs (see README): ApplicationSets enabled and Argo CD resources manageable in-cluster,
# this repo (or a fork) readable at REPO_URL, platform CLI ($PLATFORM_CLI) logged in.
# Usage: scripts/up.sh [matrix]     ("matrix" uses the nested-cluster-generator spoke variant)
source "$(dirname "$0")/common.sh"
REPO_URL="${REPO_URL:-https://github.com/martysohio/appset_bugtest.git}"   # this repo
VARIANT="${1:-plain}"

echo "Instance: $INSTANCE_NAME ($ARGOCD_SERVER)  cluster: $CLUSTER_NAME  repo: $REPO_URL @ $REPO_REVISION ${REPO_PATH:+(path $REPO_PATH)}"

render() {
  sed -e "s|REPO_URL|${REPO_URL}|g" \
      -e "s|REPO_REVISION|${REPO_REVISION}|g" \
      -e "s|CHART_PATH|$(repo_path charts/blueprint)|g" \
      -e "s|PACKAGES_PATH|$(repo_path packages)|g" \
      -e "s|CLUSTER_NAME|${CLUSTER_NAME}|g" "$1"
}
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Cluster labels the spoke AppSet's cluster generator reads.
set_demo_labels demo-tenant=demo demo-disabled=false

# 2. AppProject.
render "$DEMO_DIR/bootstrap/10-project.yaml" > "$TMP/project.yaml"
acd proj create -f "$TMP/project.yaml" --upsert

# 3. Spoke ApplicationSet.
SPOKE="$DEMO_DIR/bootstrap/20-spoke-appset.yaml"
[ "$VARIANT" = "matrix" ] && SPOKE="$DEMO_DIR/bootstrap/20-spoke-appset-matrix.yaml"
render "$SPOKE" > "$TMP/spoke.yaml"
acd appset create "$TMP/spoke.yaml" --upsert

echo
echo "Bootstrapped ($VARIANT spoke). Within ~1 min you should see demo-blueprint and 3 demo-package-* apps."
echo "  scripts/observe.sh            # live view; flags STALE tree nodes"
echo "  scripts/flip.sh true|false    # flip the tenant's disabled switch"
echo "UI: https://${ARGOCD_SERVER}/applications?proj=demo"
