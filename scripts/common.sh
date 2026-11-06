#!/usr/bin/env bash
# Shared settings for running the demo against a managed Argo CD instance.
# Nothing here uses kubectl or your current kube context. Argo CD is reached only through
# ARGOCD_SERVER + ARGOCD_AUTH_TOKEN (explicit flags, so your argocd CLI's current context is
# ignored), and cluster labels are changed only through the platform CLI named by PLATFORM_CLI.
set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${INSTANCE_NAME:?set INSTANCE_NAME to the Argo CD instance name on your platform}"
: "${ARGOCD_SERVER:?set ARGOCD_SERVER to the instance host, e.g. <instance-host>}"
: "${ARGOCD_AUTH_TOKEN:?set ARGOCD_AUTH_TOKEN to an Argo CD API token for that instance}"
: "${PLATFORM_CLI:?set PLATFORM_CLI to the platform CLI that manages cluster labels (see README)}"
ARGOCD_SERVER="${ARGOCD_SERVER#https://}"; ARGOCD_SERVER="${ARGOCD_SERVER%/}"
ORG_NAME="${ORG_NAME:-}"                      # platform org name; empty = CLI default
CLUSTER_NAME="${CLUSTER_NAME:-general-demo}"  # managed cluster the package apps deploy to
REPO_REVISION="${REPO_REVISION:-HEAD}"
REPO_PATH="${REPO_PATH:-}"                    # subdir of REPO_URL holding charts/ and packages/ (empty = repo root)
repo_path() { echo "${REPO_PATH:+${REPO_PATH%/}/}$1"; }

acd() { argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --grpc-web "$@"; }
api() { curl -s --max-time 20 -H "Authorization: Bearer ${ARGOCD_AUTH_TOKEN}" "https://${ARGOCD_SERVER}/api/v1/$1"; }
# Platform CLI cluster commands: `$PLATFORM_CLI argocd cluster get|update <name> --instance-name ...`
akc() {
  if [ -n "$ORG_NAME" ]; then
    "$PLATFORM_CLI" argocd cluster "$@" --instance-name "$INSTANCE_NAME" --organization-name "$ORG_NAME"
  else
    "$PLATFORM_CLI" argocd cluster "$@" --instance-name "$INSTANCE_NAME"
  fi
}

# Set demo-* labels on the managed cluster while keeping every other label and annotation.
# It's not known whether `<platform-cli> argocd cluster update --label` merges or replaces, so the
# existing labels/annotations are read back and passed through unchanged.
# Usage: set_demo_labels demo-tenant=demo demo-disabled=false     (no args = remove all demo-* labels)
set_demo_labels() {
  local cur n args=() kv
  cur="$(akc get "$CLUSTER_NAME" -o json)"
  for field in labels annotations; do
    n="$(jq --arg f "$field" '[paths(objects) | select(.[-1]==$f)] | length' <<<"$cur")"
    if [ "$n" -gt 1 ]; then
      echo "ERROR: found $n '$field' maps in 'cluster get' output; refusing to guess which one" >&2
      echo "       is the cluster's. Set the labels in the platform UI instead." >&2
      return 1
    fi
  done
  while IFS= read -r kv; do [ -n "$kv" ] && args+=(--label "$kv"); done < <(jq -r '
    [paths(objects) as $p | select($p[-1]=="labels") | getpath($p)] | add // {}
    | to_entries[] | select(.key|startswith("demo-")|not) | "\(.key)=\(.value)"' <<<"$cur")
  while IFS= read -r kv; do [ -n "$kv" ] && args+=(--annotation "$kv"); done < <(jq -r '
    [paths(objects) as $p | select($p[-1]=="annotations") | getpath($p)] | add // {}
    | to_entries[] | "\(.key)=\(.value)"' <<<"$cur")
  for kv in "$@"; do args+=(--label "$kv"); done
  echo "$PLATFORM_CLI argocd cluster update $CLUSTER_NAME ${args[*]:-}"
  akc update "$CLUSTER_NAME" ${args[@]+"${args[@]}"} -o json >/dev/null
}
