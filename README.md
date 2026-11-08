# NRP GitLab

Manifests for gitlab.nrp-nautilus.io, running in the `gitlab` namespace on Nautilus.
ArgoCD (`argocd/application.yaml`, in the `argo` namespace) syncs everything under
`manifests/` with auto-sync, prune and self-heal on.

| Directory | Contents |
|---|---|
| `manifests/gitlab` | GitLab omnibus Deployment, its `gitlab.rb` ConfigMap, Services, Ingress, Certificate |
| `manifests/registry` | Container registry (`gitlab-reg`), its Redis, Ingresses, ServiceMonitor |
| `manifests/runners` | GitLab runner Deployments: `gitlab-runner-kata` (tag `docker`), `gitlab-runner-kata-default` (untagged), and `gitlab-runner-gitlab`/`gitlab-runner-sdsc` for other GitLab servers. All run their jobs in Kata VMs in `gitlab-ci-kata` |
| `manifests/ai-gateway` | Duo AI gateway |
| `manifests/database` | Zalando `postgresql` cluster `gitlab-db` |
| `manifests/ci-kata` | Objects in namespace `gitlab-ci-kata` (job pods of `gitlab-runner-kata` and `gitlab-runner-kata-default`): admission policy, NetworkPolicies, quota. The namespace itself is created through the nrp.ai portal, not here: the `nautilus-admission` webhook rejects pods in namespaces without a portal registration |
| `manifests/storage` | Standalone PVCs (including the 6Ti GitLab data volume) |

The stopped KubeVirt VM `arm-runner` still exists in the namespace but is deliberately not in git. A stopped VM never
reports Healthy, and the app syncs with `PruneLast=true`, so every sync that pruned something waited for it forever.
Its disk PVC `arm-runner-hd` is still tracked in `manifests/storage`. The docker.sock runner VMs `runner1`/`runner2`
were deleted and replaced by `gitlab-runner-kata`.

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

`gitlab-ci-kata` is also listed in `portal.pod_runtime_exceptions` of ConfigMap `kube-system/nautilus-config` (a live
change too), so `nautilus-admission` doesn't cap its bare pods at 16 cores / 32 GB of limits or 6 hours. Docker-build
jobs need that (dind alone is 48Gi). If the entry is lost, they fail to start.

## Default runner (`gitlab-runner-kata-default`, untagged)

The instance's default runner: it runs untagged jobs, and jobs tagged `kata-default`, in the same namespace, on the
same Kata VMs and under the same guard rails as `gitlab-runner-kata`, but nothing is privileged and there is no dind
service. It replaced `gitlab-runner-general`, whose jobs ran in the `gitlab` namespace next to GitLab. Tags and
run-untagged are set on the runner record in GitLab (Admin > CI/CD > Runners), not in this repo.

Each job gets 1 CPU requested / 4 CPU limit and 8Gi of memory. A job can raise that with CI/CD variables, up to the
caps in `gitlab-runner-kata-default-configmap.yaml`:

| Variable | Default | Max |
|---|---|---|
| `KUBERNETES_CPU_LIMIT` | 4 | 12 |
| `KUBERNETES_CPU_REQUEST` | 1 | 2 |
| `KUBERNETES_MEMORY_LIMIT` | 8Gi | 24Gi |
| `KUBERNETES_MEMORY_REQUEST` | 8Gi | 24Gi |
| `KUBERNETES_SERVICE_CPU_LIMIT` | 1 | 2 |
| `KUBERNETES_SERVICE_MEMORY_LIMIT` / `_REQUEST` | 1Gi | 4Gi |

Set the memory request along with the limit: Kata sizes the VM from the limit, but the scheduler only counts the
request. At the caps a pod stays under the `nautilus-admission` limit for bare pods, so default jobs don't depend on
the exemption above.

Images are always pulled (`pull_policy = always`, and jobs can't choose another policy). With `if-not-present`, a job
could run another project's private image from the node's cache without having the credentials to pull it.

`manifests/ci-kata/networkpolicy-kube-api.yaml` lets this runner's jobs, and only these, reach the API server's public
endpoints on 6443, for projects that deploy to Nautilus with `kubectl`/`helm` and a kubeconfig in a CI variable.

## Runners for other GitLab servers (`gitlab-runner-gitlab`, `gitlab-runner-sdsc`)

`gitlab-runner-gitlab` takes jobs from gitlab.com and `gitlab-runner-sdsc` from hpc-gitlab.sdsc.edu (tokens in
`gitlab-runner-token`, keys `gitlab` and `sdsc`). Their jobs run like the default runner's, in Kata VMs in
`gitlab-ci-kata` (`gitlab-runner-kata-external-config`), but without the API-server egress. Their cache lives under its
own prefix (`external/<server>`) in the shared bucket, because project IDs from different GitLab servers collide.

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

To re-export GitLab, the registry, the AI gateway, the database CR, the VM and the PVCs from the cluster, run
`scripts/export.sh` (needs `kubectl` and `yq`). The runners and `manifests/ci-kata` are hand-written; it leaves them alone.
