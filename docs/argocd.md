# Argo CD

The GitOps controller for this cluster. This document covers the decision, the one-time bootstrap, and how Argo CD ends up managing itself.

## Decision: Argo CD, not Flux

[ARCHITECTURE.md](ARCHITECTURE.md) laid out the tradeoff and left it open. Settled on **Argo CD**, for the reason recorded there: the built-in UI makes sync state, drift, and diffs *visible*, and the point of this cluster is to learn by watching GitOps actually happen rather than by inferring it from controller logs. Flux's argument — that its CRD-per-concern model forces a deeper understanding of the reconciliation machinery — is a real one, and is the reason to revisit this if the visual on-ramp ever stops teaching anything new.

A second, more concrete reason: Keycloak is the next thing landing, and Argo CD speaks OIDC directly and ships a first-class RBAC model mapping OIDC group claims to roles. That's exactly the shape of the next piece of work.

## Layout

```
gitops/
├── bootstrap/
│   └── root.yaml                  # the one manual apply, ever
├── infra/
│   └── argocd/
│       ├── application.yaml       # Argo CD, managed by Argo CD
│       └── values.yaml            # the entire Argo CD config surface
└── apps/                          # workloads (empty for now)
```

The convention: **a directory becomes a deployed component the moment it contains an `application.yaml`.** The root app recurses through `gitops/` looking for exactly that filename, and creates an Argo CD `Application` for each one it finds. Adding a component is a new directory plus a commit; removing one is deleting the directory.

## The chicken-and-egg problem

Argo CD deploys everything in this cluster from git. But Argo CD itself has to get into the cluster somehow, and it can't deploy itself before it exists. Something has to be done by hand exactly once.

The trick is to make that manual step produce *byte-identical output* to what Argo CD will later produce on its own. So the bootstrap is not `helm install` — it's `helm template | kubectl apply`. `helm install` would create a Helm release, with its own release metadata and ownership annotations that Argo CD neither creates nor understands; Argo CD would then be perpetually reconciling against something slightly different from what it would have made. `helm template` just renders manifests, which is precisely what Argo CD's repo-server does. The handoff becomes a no-op.

## Bootstrap

Prerequisites: `kubectl` pointed at the cluster, `helm` installed, and the `terraform` layer already applied.

```sh
# 1. The namespace. The chart doesn't create it.
kubectl create namespace argocd

# 2. Render and apply the same chart+values Argo CD will manage itself with.
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm template argocd argo/argo-cd \
  --version 10.2.2 \
  --namespace argocd \
  --values gitops/infra/argocd/values.yaml \
  | kubectl apply -n argocd --server-side -f -

# 3. Wait for it to come up.
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

# 4. Hand over control. From here, Argo CD manages Argo CD.
kubectl apply -f gitops/bootstrap/root.yaml
```

`--server-side` on step 2 is not optional: Argo CD's CRDs exceed the 256KB annotation limit that client-side apply relies on, and a plain `kubectl apply` fails with `metadata.annotations: Too long`. The self-management Application sets `ServerSideApply=true` for the same reason.

Step 4 is the handover. The root app finds `gitops/infra/argocd/application.yaml`, creates an `argocd` Application from it, and that Application renders the identical chart and values. It should report `Synced` almost immediately, having found nothing to change.

### If `helm repo add` can't reach argoproj.github.io

Some networks can't reach the chart repo. The chart is also published as a release asset, and `helm template` accepts a local tarball:

```sh
gh release download argo-cd-10.2.2 --repo argoproj/argo-helm --pattern '*.tgz'
helm template argocd ./argo-cd-10.2.2.tgz --namespace argocd \
  --values gitops/infra/argocd/values.yaml \
  | kubectl apply -n argocd --server-side -f -
```

This changes nothing about the result — same chart, same version, same rendered output. It only affects where the chart bytes came from. Argo CD's repo-server fetches the chart from inside the cluster and is unaffected either way.

## Accessing the UI

There is no ingress yet (Phase 4), so access is via port-forward:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Then <http://localhost:8080>. Plain HTTP, because `server.insecure: true` is set — see the extended note in `values.yaml` for why that's acceptable *only* while port-forward is the sole access path, and why it has to change the moment it isn't.

The initial admin password is generated at install and stored in a secret:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Log in as `admin`. That secret is meant to be temporary — it goes away once Keycloak is issuing logins, at which point the local admin account should be disabled entirely.

## How self-management works

`gitops/infra/argocd/application.yaml` is an Application with two sources: the chart, from the Argo project's Helm repo, and this repo, referenced as `$values` so the `valueFiles` entry can point at `gitops/infra/argocd/values.yaml`. Two sources are needed because the chart and its configuration live in different places, and inlining the values into the Application manifest would make them unreadable and un-diffable.

From then on, changing Argo CD means editing `values.yaml` and committing. Upgrading Argo CD means bumping `targetRevision` and committing. Neither involves helm or kubectl.

**The failure mode worth knowing:** commit values that produce a broken Argo CD, and the thing that would apply the fix is the thing that's broken. There's no clever recovery — you re-run the bootstrap above against the corrected values, which never depends on a running Argo CD. This is the main argument for keeping `values.yaml` boring.

## What changes when Keycloak lands

Three things, all in `values.yaml`, all marked with comments there already:

1. `global.domain` — the real hostname. OIDC redirects fail without it, in a way that looks like a Keycloak problem.
2. `configs.cm.oidc.config` — issuer, client ID, and a `$oidc.keycloak.clientSecret` reference. The `$` prefix means "read this from the `argocd-secret` Secret", which is what keeps the actual secret out of this public repo.
3. `configs.rbac.policy.csv` — mapping Keycloak group claims to Argo CD roles. `policy.default` is already `role:readonly`, so an authenticated-but-unmapped identity gets read-only rather than whatever the chart default would have granted.

Getting the client secret into the cluster is its own decision (sealed-secrets, external-secrets, or once by hand) and belongs to that piece of work.
