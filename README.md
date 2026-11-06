# appset_bugtest

Reproduction for a managed Argo CD behaviour: **an Application deleted by an ApplicationSet stays
visible in its parent's resource tree.** Clicking it gives `Resource not found`. Normal and hard
refreshes don't remove it. It clears only when the application controller next does a full re-list of
the control-plane cluster (`in-cluster`), sometimes many minutes later.

It reproduces when many Applications are deleted at once **while the control plane is under refresh
load**. Without load, deletes are clean.

> Running this with Claude Code? `CLAUDE.md` has the agent-oriented instructions.

## What it deploys

```
AppSet  demo-spoke                cluster generator; reads the cluster label `demo-disabled`
 └─ App  demo-blueprint           control plane (in-cluster); Helm valuesObject disabled: "<label>"
     └─ AppSet demo-blueprint     list generator, empty when disabled -> deletes every package app
         └─ 26 x App demo-package-<name>   one ConfigMap each on the target cluster (ns demo-workloads)
```

Setting `demo-disabled=true` on the cluster makes the blueprint AppSet generate 0 apps, so it deletes
all 26 package apps in one go. Setting it back to `false` recreates them.

## Repo layout

| Path | What |
|---|---|
| `charts/blueprint` | Helm chart that renders the blueprint ApplicationSet |
| `packages/<name>` | One ConfigMap per package app (the content doesn't matter) |
| `packages-blocking/karpenter` | Same ConfigMap with a finalizer nothing removes (contrast case: stuck deletion) |
| `bootstrap/` | AppProject and the spoke ApplicationSet (plain and matrix variants) |
| `scripts/` | Set up, flip, load, observe, tear down |
| `tools/hold-test.sh` | The whole reproduction, automated |
| `tools/stale_report.py` | Summarises an observe log: stale episodes and how long they lasted |

## Prerequisites

- **Managed Argo CD instance** with **ApplicationSets** enabled, and Argo CD resources (Applications,
  ApplicationSets) manageable in the control plane via the `in-cluster` destination: `demo-blueprint`
  deploys an ApplicationSet there. Use a test instance, not production.
- **A cluster connected to that instance** (default name `general-demo`; set `CLUSTER_NAME`). The demo
  adds the labels `demo-tenant` and `demo-disabled` to it and creates the namespace `demo-workloads`.
  It keeps all other labels and annotations.
- **This repo readable by the instance.** The public default is
  `https://github.com/martysohio/appset_bugtest.git`. Set `REPO_URL` for a fork.
- **CLIs:** the platform CLI that manages the instance's clusters (logged in; set `PLATFORM_CLI` to its
  command name, and it must support `argocd cluster get|update <name> --instance-name <i> --label k=v`), `argocd` (logged in to the instance), `jq`, `curl`, `python3` with PyYAML.
- **No names already taken:** the AppProject `demo`, the ApplicationSets `demo-spoke` / `demo-blueprint`,
  and the Applications `demo-blueprint` / `demo-package-*` must not already exist on the instance.

The scripts never use `kubectl` or your kube context. They reach Argo CD only through `ARGOCD_SERVER` +
`ARGOCD_AUTH_TOKEN`, and change cluster labels only through `$PLATFORM_CLI`.

## Run it

```bash
export PLATFORM_CLI=<platform-cli>              # command name of the platform CLI
export INSTANCE_NAME=<instance-name>            # plus ORG_NAME=<org> if not your CLI default
export ARGOCD_SERVER=<instance-host>
source scripts/env-from-argocd-cli.sh           # takes ARGOCD_AUTH_TOKEN from your argocd login
# optional: CLUSTER_NAME (default general-demo), REPO_URL, REPO_REVISION (default HEAD)

scripts/up.sh                  # create project + spoke AppSet; ~1 min later 26 healthy package apps
tools/hold-test.sh             # automated reproduction, ~10-30 min (details below)
scripts/flip.sh false          # restore the package apps afterwards
scripts/down.sh                # remove everything the demo created
```

### What `tools/hold-test.sh` does
1. Re-enables the tenant and waits until all 26 package apps are Synced and Healthy.
2. Starts `scripts/load.sh`: about 8 `?refresh=normal` requests per second against the package apps
   for 75s.
3. While the load is running, disables the tenant, so all 26 apps get deleted.
4. Waits 60s, then checks for deleted apps still in `demo-blueprint`'s resource tree.
5. If any are stuck: holds without touching anything for `HOLD_MINUTES` (default 15), then tries a
   normal refresh, a hard refresh, and an `in-cluster` cache invalidation, recording which one clears
   it.
6. If nothing is stuck, it retries, up to 3 attempts.

It writes `hold-test-<timestamp>/events.log` (timeline and `RESULT:` line) and `observe.log`.
Summarise with:
```bash
python3 tools/stale_report.py hold-test-*/observe.log hold-test-*/events.log
```

### Manual exploration
```bash
scripts/observe.sh             # live REAL / TREE / ASET / CLICK view; prints STALE in red
scripts/load.sh 120 8          # refresh load: seconds, requests per second
scripts/flip.sh true|false     # disable / enable the tenant
scripts/storm.sh 6 8           # flap disabled on and off: cycles, seconds between flips
```
`observe.sh` columns:
- **REAL:** Application objects that exist.
- **TREE:** Application nodes in `demo-blueprint`'s resource tree (what the UI draws).
- **ASET:** the blueprint AppSet's `status.resources`.
- **CLICK:** the HTTP status of the `GetResource` call the UI makes when a node is clicked.

**STALE** means a name is in TREE (or ASET) but not in REAL.

## Expected results

| Condition | Typical result |
|---|---|
| Disable with no load | All apps gone from REAL, TREE and ASET within ~5–15s |
| Disable under load | 1–2 of the 26 apps stay in TREE as "Progressing / Pending deletion" and CLICK returns 404. They survive normal and hard refresh, and clear at the next full re-list of `in-cluster` (an `in-cluster` invalidation followed by a reconcile, a controller restart, or the periodic resync), sometimes 10+ minutes later |
| Invalidate the **target** cluster (not `in-cluster`) | No effect |

Reproduced 4 out of 4 times under load on a managed instance running Argo CD v3.5.5.

## Other scenarios

- **Restart dependency (matrix generator):** `scripts/up.sh matrix` nests the cluster generator inside
  a matrix generator. Then run `scripts/flip.sh true` and `scripts/flip.sh false`, and check whether
  `demo-blueprint` re-renders without an ApplicationSet controller restart.
- **Stuck deletion (contrast case):** copy `packages-blocking/karpenter/configmap.yaml` over
  `packages/karpenter/configmap.yaml` in a fork, then `scripts/flip.sh true`. `demo-package-karpenter`
  stays with a deletionTimestamp until you release it:
  `argocd app patch-resource demo-package-karpenter --kind ConfigMap --resource-name karpenter-demo --patch '{"metadata":{"finalizers":null}}' --patch-type application/merge-patch+json`.
- **Mitigation for the mass delete:** add `spec.syncPolicy.applicationsSync: create-update` to
  `charts/blueprint/templates/appset.yaml` in a fork. The package apps then survive `flip.sh true`.

## Cleanup
`scripts/down.sh` deletes the spoke AppSet (which removes the blueprint and every package app), the
`demo` project and the `demo-*` cluster labels. The `demo-workloads` namespace on the target cluster
is left behind, because `CreateNamespace` doesn't prune it.
