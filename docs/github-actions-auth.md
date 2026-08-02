# GitHub Actions → GCP: state bucket + authentication

Two things need to exist in GCP *before* `.github/workflows/terraform.yml` can run: a place for remote state to live, and a way for GitHub Actions to authenticate. Both are one-time, manual setup — chicken-and-egg, since Terraform can't create the very backend it needs in order to run.

Run everything below locally, once, with `gcloud` authenticated as yourself (you already have this, from creating the cluster).

## 1. Remote state bucket

```sh
PROJECT_ID="your-gcp-project-id"
BUCKET="${PROJECT_ID}-tf-state"

gsutil mb -p "${PROJECT_ID}" -l europe-west1 "gs://${BUCKET}"

# Versioning: if state ever gets corrupted or a bad apply overwrites it,
# you can roll back to a previous version instead of losing it outright.
gsutil versioning set on "gs://${BUCKET}"

# Uniform bucket-level access: simpler, more predictable IAM (one policy
# for the whole bucket) instead of per-object ACLs.
gsutil uniformbucketlevelaccess set on "gs://${BUCKET}"
```

Put this bucket name in `terraform/backend.hcl` (copy from `backend.hcl.example`) for local use, and as the `TF_STATE_BUCKET` repo variable in GitHub (Settings → Secrets and variables → Actions → Variables) for CI.

## 2. Authentication — two options

Both need a dedicated service account first (don't use your own user account for CI — if the key or credentials ever leaked, you'd be rotating your own login, not a scoped-down bot account):

```sh
gcloud iam service-accounts create terraform-ci \
  --project="${PROJECT_ID}" \
  --display-name="Terraform CI"

SA_EMAIL="terraform-ci@${PROJECT_ID}.iam.gserviceaccount.com"

# Manage GKE clusters and node pools.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/container.admin"

# Act as itself when GKE creates resources on its behalf.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/iam.serviceAccountUser"

# Read compute metadata (instance groups behind the node pool, etc).
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/compute.viewer"

# Create and manage networking resources — static IPs, and later anything
# else the ingress layer needs. compute.viewer above is read-only and is
# NOT sufficient; see the note below.
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/compute.networkAdmin"

# Access to the state bucket specifically.
gsutil iam ch "serviceAccount:${SA_EMAIL}:roles/storage.objectAdmin" "gs://${BUCKET}"
```

### On `compute.networkAdmin`, and how it got added

It wasn't in the original set, and the first `terraform apply` that tried to reserve a static IP for ingress-nginx failed on it:

```
Error 403: Required 'compute.addresses.create' permission for
'projects/.../regions/europe-west1/addresses/ingress-nginx-ip'
Reason: forbidden, Message: Required 'compute.addresses.setLabels' permission
```

The service account had been scoped for exactly one job — run GKE — and reserving an address is a different job. `roles/compute.viewer` is read-only, so it could see addresses and not create them.

`roles/compute.networkAdmin` carries both permissions the error named (`compute.addresses.create` and `compute.addresses.setLabels`) and covers networking generally, without granting control over VMs or disks the way `roles/compute.admin` would. Narrower still would be a custom role holding only `compute.addresses.*`; that's the tighter answer and costs an extra resource to maintain. `networkAdmin` is the proportionate choice for a single-operator cluster.

The failure itself is worth keeping rather than tidying away. This service account is the one credential CI holds, and it is deliberately not project-owner, which means expanding what the pipeline can do is a visible, deliberate act rather than something that silently already worked. A 403 on a new resource type is that design functioning, not a misconfiguration.

From here, pick one:

### Option A — Workload Identity Federation (what the workflow uses)

No key file, ever. GitHub's own OIDC token gets exchanged for short-lived GCP credentials at runtime, scoped to this one repo.

```sh
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
REPO="Koufan-De-King/google-k8s" # org/repo, exact match required

# A pool is a container for external identities GCP will trust.
gcloud iam workload-identity-pools create "github-pool" \
  --project="${PROJECT_ID}" --location="global" \
  --display-name="GitHub Actions Pool"

# A provider inside that pool, trusting GitHub's OIDC issuer specifically,
# and mapping GitHub's token claims (e.g. which repo it came from) into
# attributes GCP can check.
#
# --attribute-condition is REQUIRED here, and GCP will reject the command
# without it. The reason is worth understanding rather than pasting past:
# the issuer (token.actions.githubusercontent.com) is shared by every
# GitHub Actions run on earth. Trusting the issuer alone would mean any
# repo's workflow could present a valid token to this pool. The condition
# is the filter that narrows "GitHub said so" down to "GitHub said so, and
# it was this specific repo."
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="${PROJECT_ID}" --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${REPO}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Restrict impersonation of the service account to tokens whose
# `repository` claim matches this exact repo — anyone else's GitHub Actions
# run, even using the same OIDC issuer, is rejected.
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${REPO}"
```

Repo **variables** to set (Settings → Secrets and variables → Actions → Variables — these aren't secret, so `vars` not `secrets`):

| Variable | Value |
|---|---|
| `GCP_PROJECT_ID` | `${PROJECT_ID}` |
| `TF_STATE_BUCKET` | `${BUCKET}` |
| `GCP_WIF_PROVIDER` | `projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `${SA_EMAIL}` |

Nothing to add under **Secrets** — that's the point of WIF.

#### Verifying it actually worked

The pool and the provider are separate resources, and it's entirely possible to end up with the pool created and the provider silently missing — which is exactly what happened on the first attempt here, because the `create-oidc` command was run without the required `--attribute-condition` and was rejected. The failure only surfaced much later, on the first CI run.

Check both, rather than assuming:

```sh
gcloud iam workload-identity-pools list \
  --location=global --project="${PROJECT_ID}"

gcloud iam workload-identity-pools providers list \
  --location=global --workload-identity-pool="github-pool" \
  --project="${PROJECT_ID}"
```

Both must return a row. An empty provider list with a healthy-looking pool is the failure mode described above, and it produces this on the GitHub side:

```
failed to generate Google Cloud federated token for
//iam.googleapis.com/projects/.../providers/github-provider:
{"error":"invalid_target","error_description":"The target service indicated by
the \"audience\" parameters is invalid. This might either be because the pool or
provider is disabled or deleted or because it doesn't exist."}
```

The error names three possible causes and gives no way to tell them apart from GitHub's side — the two `list` commands above are how you find out which one it is. Note that the project *number* (not ID) in `GCP_WIF_PROVIDER` must also match; a mismatch there produces the same message.

### Option B — Service account JSON key (simpler, weaker)

Skip the pool/provider/binding steps above entirely. Instead:

```sh
gcloud iam service-accounts keys create terraform-ci-key.json \
  --iam-account="${SA_EMAIL}"
```

Paste the full contents of `terraform-ci-key.json` into a GitHub **secret** named `GCP_SA_KEY` (Settings → Secrets and variables → Actions → Secrets), then delete the local file — it's a live credential from the moment it's created.

To use it, edit `.github/workflows/terraform.yml`: comment out the "Authenticate to GCP (Workload Identity Federation)" step and uncomment the "Authenticate to GCP (service account key)" step below it. Nothing else in the workflow or in `terraform/` needs to change either way.

**Tradeoff to be clear-eyed about:** this key doesn't expire on its own, and if it ever leaks (logged accidentally, repo goes public, etc.) it's usable until you manually revoke it. WIF's tokens are short-lived and minted fresh per run, so there's no standing credential to leak in the first place. Reasonable to start with a key just to get moving faster, but worth migrating to WIF before this repo does anything you'd be upset to lose control of.

## Summary: what each option needs

| | WIF | SA key |
|---|---|---|
| One-time GCP setup | Pool + provider + IAM binding | Just the key |
| Stored in GitHub | Nothing secret (2 identifiers as `vars`) | 1 long-lived secret |
| Workflow `permissions` | needs `id-token: write` | not required |
| Ongoing risk | None — tokens are short-lived and minted per run | Key is valid until manually rotated/revoked |
