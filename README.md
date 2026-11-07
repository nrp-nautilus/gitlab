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
| `manifests/vms` | KubeVirt VM `arm-runner` (stopped). The docker.sock runner VMs `runner1`/`runner2` were replaced by `gitlab-runner-kata` |
| `manifests/ci-kata` | Objects in namespace `gitlab-ci-kata` (job pods of `gitlab-runner-kata`): admission policy, NetworkPolicy, quota. The namespace itself is created through the nrp.ai portal, not here: the `nautilus-admission` webhook rejects pods in namespaces without a portal registration |

## Kata runner (`gitlab-runner-kata`, tag `docker`)

Every job runs as a pod in `gitlab-ci-kata` on the `kata` RuntimeClass, so it gets its own VM, which is thrown away
after the job. The runner adds a privileged `docker:dind` service to each job and sets `DOCKER_HOST=tcp://docker:2375`, so
`docker build` jobs written for the old docker.sock runners work unchanged. Privileged here means root inside the job's VM:
kata-deploy configures containerd with `privileged_without_host_devices = true`, so no node devices are passed in.

The guard rails, all of which must stay in place:

- `manifests/ci-kata/admission-policy.yaml` rejects any pod in `gitlab-ci-kata` that isn't on the `kata` runtime, uses
  hostPath, host namespaces or hostPort, uses a service account other than `ci-job`, or mounts a token.
- `gitlab-ci-kata` is in the `excludedNamespaces` of Gatekeeper's `psp-privileged-container` constraint. This is a live
  change, because Gatekeeper constraints aren't kept in this repo. If the constraint is re-applied from its source,
  the exemption disappears and jobs fail to start; that fails safe.
- `manifests/ci-kata/networkpolicy.yaml` allows DNS and the public internet only: no pod, service or private ranges,
  no link-local addresses, and not the API server.
- Kata runs only on the nodes labelled `katacontainers.io/kata-runtime=true` (UNL), several of which carry the
  `nautilus.io/testing=kata` taint that the job pods tolerate.
| `manifests/storage` | Standalone PVCs (including the 6Ti GitLab data volume) |

## Secrets

This repo is public, so Secrets are committed only as SealedSecrets (`*-sealedsecret.yaml`, next to
the workload that uses them). They're encrypted with the cluster's sealed-secrets controller key
(`pub-cert.pem`, namespace `sealed-secrets-operator`). To update one, change the Secret in the
cluster, run `scripts/seal.sh <name>` and commit. For a new one, add it to `SECRETS` in the script
and run `DIR=manifests/<component> scripts/seal.sh <name>`.
To fetch a fresh cert after the controller rotates keys:

    kubeseal --controller-namespace sealed-secrets-operator --controller-name sealed-secrets --fetch-cert > pub-cert.pem

The controller won't take over a Secret it didn't create unless the Secret has
`sealedsecrets.bitnami.com/managed: "true"` on it. Annotate an existing Secret like that before
its SealedSecret first syncs.

SealedSecrets have `Prune=false,Delete=false`, because deleting a SealedSecret garbage-collects its Secret.

## Not in git

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
