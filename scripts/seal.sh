#!/usr/bin/env bash
# Seal Secrets from the gitlab namespace into SealedSecrets under manifests/.
# Each Secret is piped straight into kubeseal; plaintext never touches disk.
# A Secret that's already sealed is rewritten in place; a new one goes to DIR.
# usage: [DIR=manifests/<component>] scripts/seal.sh [secret-name...]
#        (default: every Secret in SECRETS)
set -euo pipefail
cd "$(dirname "$0")/.."
CONTEXT=${CONTEXT:-nautilus-readonly}
CERT=${CERT:-pub-cert.pem}
DIR=${DIR:-manifests/gitlab}

# Hand-made Secrets that workloads use. Operator, cert-manager and per-job
# Secrets are left to the controllers that create them.
SECRETS=(
  ai-gateway-jwt authentik-oauth github-oauth gitlab gitlab-oauth
  gitlab-reg-secrets gitlab-runner-token gitlab-ssh-host-keys google-oauth
  registry-redis runner-cache runner1-userdata runner2-userdata
  runners-pub-keys ssl-key
  # Not mounted anywhere; kept as the backup of GitLab's encryption keys.
  gitlab-secrets-json
)
[ $# -gt 0 ] && SECRETS=("$@")

for s in "${SECRETS[@]}"; do
  out=$(find manifests -name "$s-sealedsecret.yaml" | head -1)
  out=${out:-$DIR/$s-sealedsecret.yaml}
  kubectl --context "$CONTEXT" -n gitlab get secret "$s" -o json |
    jq '{apiVersion, kind, type, data,
         metadata: (.metadata | {name, namespace, labels}
           + {annotations: ((.annotations // {}) | del(."kubectl.kubernetes.io/last-applied-configuration"))})}
        | del(.metadata[] | select(. == null or . == {}))' |
    kubeseal --cert "$CERT" --format yaml |
    yq '.metadata.annotations["argocd.argoproj.io/sync-options"] = "Prune=false,Delete=false"
        | del(.metadata.creationTimestamp, .spec.template.metadata.creationTimestamp)' \
    > "$out"
  echo "sealed $s -> $out"
done
