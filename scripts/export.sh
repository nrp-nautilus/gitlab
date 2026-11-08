#!/usr/bin/env bash
# Re-export the gitlab namespace from the cluster into manifests/, stripping
# server-set fields. Secrets and operator-owned objects are left out on purpose;
# see README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
CLEAN=scripts/clean.yq
R=manifests
CONTEXT=${CONTEXT:-nautilus-readonly}
# Only the objects listed below are rewritten. Everything else is hand-written
# and left alone: the runners (manifests/runners), manifests/ci-kata, and the
# SealedSecrets, which come from scripts/seal.sh. If an object is removed from
# the list, delete its file by hand.
while read -r dir objs; do
  mkdir -p "$R/$dir"
  for o in $objs; do
    f="$R/$dir/${o#*/}-${o%/*}.yaml"
    kubectl --context "$CONTEXT" -n gitlab get "$o" -o yaml > "$f"
    yq -i --from-file "$CLEAN" "$f"
  done
done <<'LIST'
gitlab deployment/gitlab service/gitlab service/gitlab-ssh configmap/gitlab-config ingress/gitlab-nrp-nautilus certificate/gitlab-nrp-nautilus
registry deployment/gitlab-reg service/gitlab-registry service/registry-import-s3 configmap/registry-config ingress/gitlab-registry-nrp-nautilus ingress/gitlab-registry-old-nrp-nautilus servicemonitor/registry statefulset/registry-redis service/registry-redis-headless service/registry-redis-master configmap/registry-redis-config
ai-gateway deployment/ai-gateway service/ai-gateway
database postgresql/gitlab-db
vms virtualmachine/arm-runner
storage persistentvolumeclaim/arm-runner-hd persistentvolumeclaim/gitlab persistentvolumeclaim/gitlab-state persistentvolumeclaim/makisu-redis persistentvolumeclaim/runner-hd
LIST
for f in "$R"/storage/*.yaml "$R"/vms/*.yaml "$R"/database/*.yaml; do
  yq -i '.metadata.annotations["argocd.argoproj.io/sync-options"] = "Prune=false,Delete=false" | .metadata |= (pick(["name","namespace"]) * .)' "$f"
done
