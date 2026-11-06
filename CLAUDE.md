# Running this reproduction with Claude Code

You are helping someone reproduce "deleted Application stays in the parent's resource tree" on an
managed Argo CD instance. `README.md` explains the setup and what each script does. Read it first.

## Safety rules (follow strictly)

- **Use a test instance only.** The demo creates and deletes Applications, an AppProject and
  ApplicationSets, and changes labels on a connected cluster. Before running anything, confirm with
  the user the instance name (`INSTANCE_NAME`), the platform CLI (`PLATFORM_CLI`), its host (`ARGOCD_SERVER`) and the target cluster
  (`CLUSTER_NAME`), and that it's a test instance.
- **Don't use `kubectl`** for this demo, and never touch the user's current kube context. It may point
  at production. The scripts only use the Argo CD API and `$PLATFORM_CLI`. Keep it that way.
- **Use the scripts' own credential handling.** The scripts pass `--server`/`--auth-token` explicitly
  and ignore the user's current argocd CLI context. Don't run bare `argocd` commands against whatever
  context happens to be current.
- **Check before creating anything:** that no AppProject `demo`, ApplicationSet `demo-spoke` /
  `demo-blueprint` or Applications `demo-blueprint` / `demo-package-*` already exist. If any do, stop
  and ask.
- **Look at the cluster's labels and annotations before the first label change.** Run
  `$PLATFORM_CLI argocd cluster get "$CLUSTER_NAME" --instance-name "$INSTANCE_NAME" -o json` and inspect
  them. `set_demo_labels` in `scripts/common.sh` preserves them; check the printed `cluster update`
  command the first time.
- **Never print, log or commit tokens.** Get the token with `source scripts/env-from-argocd-cli.sh`.
  This repo is public: don't commit results, logs, instance hostnames or tokens to it.
- **Before `scripts/down.sh` or `scripts/flip.sh true`, ask the user.** Both delete Applications.

## Setup

```bash
export PLATFORM_CLI=<platform-cli> INSTANCE_NAME=<instance> ARGOCD_SERVER=<instance-host>   # confirm all with the user
source scripts/env-from-argocd-cli.sh
API() { curl -s --max-time 20 -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/$1"; }
API "projects" | jq -r '.items[].metadata.name' | grep -x demo && echo "CONFLICT: project demo exists"
API "applicationsets" | jq -r '.items[]?.metadata.name' | grep -E '^demo-(spoke|blueprint)$' && echo "CONFLICT"
# confirm with the user that the instance allows Applications/ApplicationSets to target in-cluster (argocd ns)
scripts/up.sh
```
Wait until 26 `demo-package-*` apps are Synced and Healthy:
`API "applications?projects=demo" | jq '[.items[]|select(.status.health.status=="Healthy")]|length'`.

Shell notes:
- Run the scripts with `bash`.
- If your Bash tool runs zsh, don't rely on word-splitting unquoted variables.
- `scripts/common.sh` uses `BASH_SOURCE`, so source it only from bash.
- On macOS there is no `timeout` command; run long commands in the background instead.

## Run the reproduction

`tools/hold-test.sh` takes 10–30 minutes, so run it in the background and wait for it to finish. Don't
poll. It writes `hold-test-<timestamp>/` in the current directory. Write that somewhere outside this
repo, or don't commit it.

```bash
tools/hold-test.sh 3          # up to 3 attempts; HOLD_MINUTES=15 by default
```
Afterwards:
```bash
cat hold-test-*/events.log
python3 tools/stale_report.py hold-test-*/observe.log hold-test-*/events.log
```

Caveats:
- `load.sh` sends `?refresh=normal` GETs. Argo CD can hold such a request open for an app deleted
  mid-request. The scripts set curl `--max-time`, so that can't stall the run.
- The control plane may redeploy during the test (managed control planes may resize under load). That's expected; it
  can make stuck entries clear sooner.

## What to report back to the user

1. Whether it reproduced, and on which attempt: the `RESULT:` line from `events.log`.
2. Which apps were stuck, for how long, and what cleared them (no intervention, normal refresh, hard
   refresh, or `in-cluster` invalidation). Use `stale_report.py`.
3. Whether CLICK returned 404 for the stuck nodes (the "Resource not found" the UI shows), and whether
   they showed as "Progressing / Pending deletion".
4. The instance's Argo CD and agent versions:
   `curl -s "https://$ARGOCD_SERVER/api/version" | jq -r .Version` (Argo CD), plus the platform/agent version if the user can provide it.
5. Anything unexpected: errors, apps that never came back, timing very different from `README.md`.

State what was observed versus inferred. If nothing reproduced in 3 attempts, say so; don't stretch the
evidence.

## Cleanup
Ask first, then run `scripts/flip.sh false` to restore the apps, or `scripts/down.sh` to remove
everything. `down.sh` waits for the apps to be deleted, then removes the project and the `demo-*`
cluster labels.
