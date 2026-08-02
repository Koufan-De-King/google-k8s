# Every value below was hardcoded in the raw plan the gcloud console
# generated (project ID, cluster name, zone, node count...). None of that
# belongs in version-controlled .tf files: it's either specific to your GCP
# project (project_id), specific to this one cluster (cluster_name, zone),
# or a knob you'll want to tune later without editing code (node_count,
# machine_type, disk_size_gb). Turning them into variables is what makes
# this config reusable instead of a one-off script.
#
# None of these are secret — they're just environment-specific. Actual
# secrets (service account keys, etc.) never go in .tf/.tfvars files at all;
# see docs/github-actions-auth.md.

variable "project_id" {
  description = "GCP project ID the cluster lives in. No default on purpose — forces you to pass it explicitly (via -var, TF_VAR_project_id, or a GitHub Actions secret) so it's never accidentally wrong."
  type        = string
}

variable "region" {
  description = "GCP region, used for regional resources (e.g. the future state bucket, artifact registry, etc.). Not the same as `zone` below."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone the cluster runs in. kubia is a zonal (single-zone) cluster, not regional — cheaper, but the control plane and all nodes live in one zone, so a zone outage takes the whole cluster down. Fine for a homelab; worth revisiting if this ever needs real uptime guarantees."
  type        = string
  default     = "europe-west1-b"
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "kubia"
}

variable "node_pool_name" {
  description = "Name of the node pool. Matches the real pool name (\"default-pool\") so this config accurately represents what's actually running, rather than inventing a new name that would require renaming/migrating real infrastructure."
  type        = string
  default     = "default-pool"
}

variable "node_count" {
  description = "Number of nodes in the pool."
  type        = number
  default     = 3
}

variable "machine_type" {
  description = "GCE machine type for each node."
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size per node, in GB. Deliberately 50 (not GKE's 100GB default) — at 100GB x 3 nodes this project would blow past the 250GB persistent-disk quota on a GCP free-tier account."
  type        = number
  default     = 50
}

variable "manage_default_node_pool_removal" {
  description = <<-EOT
    Whether Terraform should delete GKE's implicitly-created "default-pool"
    at cluster-creation time.

    Must stay false for the real kubia cluster. Its default-pool IS the
    already-running node pool, separately tracked as
    google_container_node_pool.default_pool below — flipping this to true
    against that cluster tells the provider to delete it for real, which is
    exactly what happened once (see docs/terraform-import.md). false means
    "don't touch it," which matches an already-imported cluster.

    Only ever pass -var="manage_default_node_pool_removal=true" for a
    genuine from-scratch apply against empty state (the destroy-and-recreate
    test in the roadmap) — there, GKE's auto-created default-pool and our
    own resource would otherwise collide on the same name.
  EOT
  type        = bool
  default     = false
}
