# NRP GitLab

Manifests for gitlab.nrp-nautilus.io, running in the `gitlab` namespace on Nautilus.
ArgoCD (`argocd/application.yaml`, in the `argo` namespace) syncs everything under
`manifests/` with auto-sync, prune and self-heal on.

| Directory | Contents |
|---|---|
| `manifests/gitlab` | GitLab omnibus Deployment, its `gitlab.rb` ConfigMap, Services, Ingress, Certificate, RBAC |
| `manifests/registry` | Container registry (`gitlab-reg`), its Redis, Ingresses, ServiceMonitor |
| `manifests/runners` | GitLab runner Deployments |
| `manifests/ai-gateway` | Duo AI gateway |
| `manifests/database` | Zalando `postgresql` cluster `gitlab-db` |
| `manifests/vms` | KubeVirt runner VMs |
| `manifests/storage` | Standalone PVCs (including the 6Ti GitLab data volume) |

## Not in git

This repo is public, so these stay in the cluster only:

- **Secrets.** Every credential is a Secret referenced by `secretKeyRef` or `secretRef`.
  Argo doesn't manage them and won't prune them.
- **The `runner1-setup` ConfigMap**, which has a runner token inline.
- **Objects other controllers own**: the operator's StatefulSet, Services, PDB and
  credential Secrets for `gitlab-db`; DataVolumes and PVCs that KubeVirt/CDI
  create; the cert-manager TLS Secret; the portal-managed `nautilus-*` RoleBindings.

## Safety

PVCs, VMs and the `postgresql` CR have `argocd.argoproj.io/sync-options: Prune=false,Delete=false`.
Removing one from git, or deleting the Application, leaves it running in the cluster.

## Changing things

Self-heal is on, so any `kubectl edit`, `kubectl scale` or `kubectl set image` gets reverted.
Make the change here instead. Two exceptions: VM `running`/`runStrategy` (so `virtctl start/stop`
still works) and the webhook's `nrp.ai/username` annotation.

To take a fresh snapshot of the cluster, run `scripts/export.sh` (needs `kubectl` and `yq`).
