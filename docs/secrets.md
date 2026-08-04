# Secrets

How secrets reach this cluster, and the convention that keeps adding the next one cheap.

## The decision

Secrets live in **GCP Secret Manager**. **External Secrets Operator** reads them and writes them into ordinary Kubernetes Secrets. ESO authenticates with **Workload Identity**, so no long-lived credential exists anywhere in the chain.

Alternatives considered and rejected:

| Approach | Where the secret rests | Why not |
|---|---|---|
| Terraform applies it | Plaintext in the state file, in the GCS bucket | Turns the state bucket into a secret store that must be guarded like one |
| Private repo, Argo CD applies | Plaintext in git history, permanently | Rotated values stay readable; one access grant exposes all history |
| Sealed Secrets | Ciphertext in this public repo | The sealing key is cluster-bound — the destroy-and-recreate test would make every sealed secret undecryptable |
| A GSA JSON key for ESO | A long-lived key in a Kubernetes Secret | Storing a permanent credential in order to fetch credentials |

## Adding a secret

Three steps. Only the first two touch GCP.

```sh
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
PROJECT_ID="project-b3b52501-db4a-4fd7-9e7"

# 1. Create the container, pinned to one region.
gcloud secrets create k8s-my-thing-password \
  --project="${PROJECT_ID}" \
  --replication-policy="user-managed" \
  --locations="europe-west1"

# 2. Add the value. By hand, never through Terraform — a
#    google_secret_manager_secret_version records the payload in state.
openssl rand -base64 32 | tr -d '\n' \
  | gcloud secrets versions add k8s-my-thing-password \
      --project="${PROJECT_ID}" --data-file=-
```

Then an `ExternalSecret` manifest in the consuming namespace. No IAM step — see below.

## The `k8s-` prefix, and why it exists

The first secret, `ARGOCD_CLIENT_SECRET`, was granted to ESO with a binding naming that one secret. That is correct least-privilege and it does not scale: every new secret needs another binding, forever.

The fix is one conditional binding covering a naming convention:

```sh
PROJECT_NUMBER="391353361618"
PRINCIPAL="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/external-secrets/sa/external-secrets"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="${PRINCIPAL}" \
  --role="roles/secretmanager.secretAccessor" \
  --condition='expression=resource.name.startsWith("projects/'"${PROJECT_NUMBER}"'/secrets/k8s-"),title=eso-k8s-prefix,description=ESO may read secrets named k8s-*'
```

One grant. ESO can read anything named `k8s-*` and nothing else in the project — not the Terraform state credentials, not anything a future service adds outside the convention.

> **So: every secret intended for the cluster is named `k8s-<component>-<purpose>`.** A secret that does not carry the prefix is invisible to ESO by construction, which makes the prefix a deliberate act of granting access rather than an accident of naming.

`ARGOCD_CLIENT_SECRET` predates this and is still covered by its own per-secret binding. Renaming it to `k8s-argocd-oidc-client` would fold it into the convention and let that binding be removed; not urgent, but worth doing before there are ten exceptions instead of one.

## Things that bite

**A wrong secret name looks exactly like an IAM failure.** Secret Manager answers a request for a non-existent secret with `PermissionDenied` on `secretmanager.versions.access`, identical to a genuine permission problem, so the API cannot be used to enumerate names. The only clue is the parenthetical *"(or it may not exist)"*.

> On `PermissionDenied`, check the name against `gcloud secrets list` **before** touching IAM.

**Rotation does not restart anything.** ESO updates the Kubernetes Secret; that is where its responsibility ends. A pod that read the value into an environment variable at startup holds the old one until it restarts, with no error and every health indicator green. Volume mounts refresh on disk within about a minute, but only if the application re-reads the file. Rotation is not finished until the consumer has restarted.

**Enabled versions accumulate.** Six version replicas are free, then $0.06 each per month. Every rotation adds one, so destroy superseded versions rather than leaving them enabled. Access operations are effectively free at this scale — 10,000 per month free, and hourly polling of one secret is about 720. Polling frequency is not the cost risk; version accumulation and multi-region replication are.

## Current secrets

| Secret Manager name | Kubernetes Secret | Namespace | Consumer |
|---|---|---|---|
| `ARGOCD_CLIENT_SECRET` | `argocd-oidc-secret` | `argocd` | Argo CD, via `$oidc.keycloak.clientSecret` |
| `k8s-keycloak-db-password` | `keycloak-db` | `keycloak` | Postgres and Keycloak, same credential |
| `k8s-keycloak-admin-password` | `keycloak-admin` | `keycloak` | Keycloak bootstrap admin |

Full background on how the trust chain works: the Workload Identity theory guide, and [github-actions-auth.md](github-actions-auth.md) for the separate GitHub-to-GCP federation it mirrors.
