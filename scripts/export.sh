#!/usr/bin/env bash
# Re-export the gitlab namespace from the cluster into manifests/, stripping
# server-set fields. Secrets, operator-owned objects and runner1-setup (it holds
# a runner token) are left out on purpose; see README.md.
set -euo pipefail
cd "$(dirname "$0")/.."
CLEAN=scripts/clean.yq
R=manifests
CONTEXT=${CONTEXT:-nautilus-readonly}
rm -rf "$R"
while read -r dir objs; do
  mkdir -p "$R/$dir"
  for o in $objs; do
    f="$R/$dir/${o#*/}-${o%/*}.yaml"
    kubectl --context "$CONTEXT" -n gitlab get "$o" -o yaml > "$f"
    yq -i --from-file "$CLEAN" "$f"
  done
done <<'LIST'
gitlab deployment/gitlab service/gitlab service/gitlab-ssh configmap/gitlab-config ingress/gitlab-nrp-nautilus certificate/gitlab-nrp-nautilus role/gitlab-admin rolebinding/gitlab-admin
registry deployment/gitlab-reg service/gitlab-registry service/registry-import-s3 configmap/registry-config ingress/gitlab-registry-nrp-nautilus ingress/gitlab-registry-old-nrp-nautilus servicemonitor/registry statefulset/registry-redis service/registry-redis-headless service/registry-redis-master configmap/registry-redis-config
runners deployment/gitlab-runner-arm64 deployment/gitlab-runner-arnoc deployment/gitlab-runner-dind deployment/gitlab-runner-docker deployment/gitlab-runner-duo deployment/gitlab-runner-general deployment/gitlab-runner-gitlab deployment/gitlab-runner-sdsc deployment/gitlab-runner-ue4 serviceaccount/runner
ai-gateway deployment/ai-gateway service/ai-gateway
database postgresql/gitlab-db
vms virtualmachine/arm-runner virtualmachine/runner1 virtualmachine/runner1-golden virtualmachine/runner2
storage persistentvolumeclaim/arm-runner-hd persistentvolumeclaim/gitlab persistentvolumeclaim/gitlab-state persistentvolumeclaim/makisu-redis persistentvolumeclaim/runner-hd
LIST
for f in "$R"/storage/*.yaml "$R"/vms/*.yaml "$R"/database/*.yaml; do
  yq -i '.metadata.annotations["argocd.argoproj.io/sync-options"] = "Prune=false,Delete=false" | .metadata |= (pick(["name","namespace"]) * .)' "$f"
done
