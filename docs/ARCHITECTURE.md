# Architecture

## The two-layer split

This repo separates concerns the same way most real GitOps setups do: **infrastructure** (the cluster itself) and **cluster state** (what runs inside it) are managed by different tools, because they change on different timescales and need different safety guarantees.

- **Terraform** provisions the GKE cluster, VPC, IAM, and node pools. This is infrastructure-as-code in the classic sense: you run `terraform plan`/`apply` yourself, changes are infrequent and deliberate, and the blast radius of a mistake is large (you can take down the whole cluster).
- **A GitOps controller** (ArgoCD or Flux — see below) runs *inside* the cluster and continuously pulls the desired state of workloads from this repo, applying it automatically. Changes here are frequent, low-risk individually, and don't require anyone to run a command — the controller notices drift and fixes it on its own.

A useful analogy: Terraform is like commissioning a building — pouring the foundation, wiring electrical, deciding room count. You don't redo that every day. The GitOps controller is like a thermostat with a very literal read of the blueprint: it's always checking "does the current state match the plan?" and nudging things back into line when it doesn't, without anyone flipping a switch.

## Why pull-based deployment (GitOps) instead of push-based CI/CD

Traditional CI/CD is push-based: a pipeline builds an image and then reaches *into* the cluster to deploy it (`kubectl apply`, `helm upgrade`, etc. run from outside). That means your CI system needs cluster credentials, and if someone manually changes something in the cluster, nothing notices or corrects it.

GitOps flips this: an agent *inside* the cluster (ArgoCD/Flux) watches this repo and pulls changes in. Benefits that matter for a learning project like this one:

- **No cluster credentials leave the cluster.** Nothing external needs prod-level access.
- **Git is the single source of truth.** `git log` on this repo *is* the deployment history.
- **Drift is self-correcting.** If you `kubectl edit` something by hand to debug, the controller will eventually revert it to match the repo — which is exactly the discipline this project is meant to enforce.

## State & applying changes

Terraform's state file (its record of what it created and each resource's last-known configuration) lives remotely in a GCS bucket, not on anyone's laptop — necessary once "applying" happens from GitHub Actions runners, which start fresh every run and have nowhere local to keep state between them. See [github-actions-auth.md](github-actions-auth.md) for the bucket and CI auth setup.

Applies happen through GitHub Actions, not by hand: a PR touching `terraform/` gets a `terraform plan` automatically so the diff is visible before anything happens, and `main` re-plans after every merge so there's always a current read on drift between the repo and reality. This mirrors the GitOps discipline described above one layer down — the infra layer doesn't get to be the one place where "just SSH in and fix it" is still allowed.

**Applying, though, is deliberately manual.** Merging to `main` does *not* apply; someone has to run the workflow from the Actions tab against `main`. That's a real departure from textbook GitOps, where merge *is* the deploy, so it's worth being explicit about why:

- The infra layer's blast radius is the entire cluster. A bad workload manifest breaks one app; a bad `terraform apply` takes down everything running on top of it.
- The safety net GitOps normally relies on — a controller that continuously reconciles and self-corrects — doesn't exist here. Terraform runs once and stops. If an apply does the wrong thing, nothing notices or reverts it.
- This repo has already lost a live node pool to an apply nobody read first (see [terraform-import.md](terraform-import.md)). Auto-apply-on-merge is precisely the pipeline shape that lets that happen unattended, at 2am, while you're doing something else.
- The credential this pipeline holds is `roles/container.admin` on the whole project. Requiring a deliberate human action to use it is cheap insurance.

The cost is one button click. Worth revisiting if this cluster ever carries something with real uptime obligations, or if enough safety (plan-diff review gates, policy checks, non-prod environments to catch mistakes first) accumulates to make unattended applies genuinely boring.

The cluster currently running (`kubia`) was created manually before this pipeline existed. It gets adopted into Terraform via `import` rather than recreated — see [terraform-import.md](terraform-import.md) for why that's safe and how it works.

## ArgoCD vs Flux — decided: Argo CD

Both are CNCF GitOps controllers that do fundamentally the same job — reconcile cluster state against a Git repo. The tradeoff is recorded below; the decision is **Argo CD**, with the reasoning in [argocd.md](argocd.md).

| | ArgoCD | Flux |
|---|---|---|
| UI | Built-in web UI showing live sync status, diffs, app health | Mostly CLI/GitOps-native; UI is a separate add-on (Weave GitOps or Flagger) |
| Mental model | "Applications" as first-class objects you can browse | Set of Kubernetes controllers (`kustomize-controller`, `helm-controller`) reconciling CRDs |
| Good for learning | Very visual — good for seeing sync state and drift at a glance | Forces you to understand the underlying controller/CRD mechanics more directly |
| Multi-tenancy / scale | Strong, used widely at scale in orgs | Also strong, slightly more composable/unix-y |

Argo CD wins on the criterion that actually matters here: this cluster exists to make GitOps *visible*, and Argo CD's UI shows sync state, drift, and per-resource diffs directly. Flux's counter-argument is real — its controller-per-concern CRD model forces a deeper understanding of the reconciliation machinery, rather than letting a UI paper over it — and is the reason to revisit this if the visual on-ramp stops teaching anything new.

The tiebreaker was the next piece of work: Keycloak. Argo CD speaks OIDC natively and ships an RBAC model that maps OIDC group claims onto roles, which is exactly the shape of that task.

## Argo CD manages Argo CD

The controller is installed by hand exactly once and reconciled from this repo thereafter — including its own upgrades. The bootstrap is deliberately `helm template | kubectl apply` rather than `helm install`, so the manual step produces byte-identical output to what Argo CD will later produce on its own; the handover is then a no-op rather than a permanent disagreement about ownership metadata.

Below Argo CD sits an "app of apps": one root `Application`, applied by hand, whose only job is to find every `application.yaml` under `gitops/` and create an `Application` from it. Adding a component is a directory plus a commit. Full detail in [argocd.md](argocd.md).

This is the same "if it's not in Git, it's not really there" premise as the Terraform layer, applied to the controller itself — with one honest asymmetry: a commit that breaks Argo CD breaks the thing that would apply the fix. That's the cost of self-management, and the reason its config is kept boring.

## Directory-to-responsibility mapping

| Path | Owned by | Purpose |
|---|---|---|
| `terraform/` | GitHub Actions (plan on PR and `main`, apply on manual dispatch) | Cluster + GCP infra |
| `gitops/bootstrap/` | Applied by hand, once | The root `Application` that creates every other one |
| `gitops/infra/` | Argo CD | Cluster-wide infra: Argo CD itself, and later ingress, cert-manager, monitoring |
| `gitops/apps/` | Argo CD | Actual workloads deployed on the cluster |
