# appset_bugtest

Git source for an ApplicationSet repro demo:

- `charts/blueprint`: Helm chart that renders an ApplicationSet with one Application per package.
  When `disabled: "true"` the list generator is empty, so the AppSet generates 0 apps and deletes them all.
- `packages/<name>`: one ConfigMap per package app.
- `packages-blocking/karpenter`: the same ConfigMap with a finalizer nothing removes, used for the stuck-deletion contrast case.
