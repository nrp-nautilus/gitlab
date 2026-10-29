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
| `manifests/secrets` | SealedSecrets for the hand-made Secrets the workloads use |

## Secrets

This repo is public, so Secrets are committed only as SealedSecrets. They're encrypted with the
cluster's sealed-secrets controller key (`pub-cert.pem`, namespace `sealed-secrets-operator`).
To add or update one, change the Secret in the cluster and run `scripts/seal.sh <name>`, then commit.
To fetch a fresh cert after the controller rotates keys:

    kubeseal --controller-namespace sealed-secrets-operator --controller-name sealed-secrets --fetch-cert > pub-cert.pem

The controller won't take over a Secret it didn't create unless the Secret has
`sealedsecrets.bitnami.com/managed: "true"` on it. Annotate an existing Secret like that before
its SealedSecret first syncs.

SealedSecrets have `Prune=false,Delete=false`, because deleting a SealedSecret garbage-collects its Secret.

## Not in git

- **The `runner1-setup` ConfigMap**, which has a runner token inline.
- **Unreferenced Secrets**: `k3s`, `runner3-userdata`, `runner4-userdata`, `runner5-userdata`,
  `runner5-userdata-secret` and `runners-pub-keys-fixed`. (`gitlab-secrets-json` isn't
  referenced either, but it's sealed as the backup of GitLab's encryption keys.)
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
