# Values other tools/steps will want to reference later — e.g. a
# `gcloud container clusters get-credentials` step in CI, or ArgoCD's
# eventual bootstrap, both need to know where the cluster actually is
# without hardcoding it a second time somewhere else.

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.kubia.name
}

output "cluster_location" {
  description = "Zone the cluster runs in."
  value       = google_container_cluster.kubia.location
}

output "cluster_endpoint" {
  description = "IP address of the cluster's Kubernetes API server."
  value       = google_container_cluster.kubia.endpoint
  sensitive   = true # not secret exactly, but not something that needs to show up in plain CI logs either
}

output "node_pool_name" {
  description = "Name of the managed node pool."
  value       = google_container_node_pool.default_pool.name
}
