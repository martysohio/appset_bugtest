#!/usr/bin/env bash
# Source this to set ARGOCD_AUTH_TOKEN from your existing `argocd login` session for ARGOCD_SERVER,
# so no token has to be pasted or stored anywhere.
#   export INSTANCE_NAME=<instance-name> ARGOCD_SERVER=<instance-host>
#   source scripts/env-from-argocd-cli.sh
: "${ARGOCD_SERVER:?set ARGOCD_SERVER first}"
ARGOCD_AUTH_TOKEN="$(python3 - "$ARGOCD_SERVER" <<'EOF'
import os, sys, yaml
server = sys.argv[1].removeprefix("https://").rstrip("/")
cfg = yaml.safe_load(open(os.path.expanduser(os.environ.get("ARGOCD_CONFIG", "~/.config/argocd/config"))))
tokens = [u.get("auth-token") for u in cfg.get("users", []) if u.get("name") == server]
if not tokens or not tokens[0]:
    sys.exit(f"no argocd CLI login found for {server}; run: argocd login {server} --sso --grpc-web")
print(tokens[0])
EOF
)" && export ARGOCD_AUTH_TOKEN && echo "ARGOCD_AUTH_TOKEN set from argocd CLI login for ${ARGOCD_SERVER}"
