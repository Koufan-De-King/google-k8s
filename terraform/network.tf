# Static external IP for the ingress-nginx load balancer.
#
# Reserved separately from the Service that uses it, on purpose: an
# ephemeral IP is released when its Service is deleted, which would
# silently invalidate the DNS A record. This address outlives any
# Kubernetes object.
#
# REGIONAL, not global. ingress-nginx is fronted by an L4 network load
# balancer, which requires a regional address in the same region as the
# cluster. A global address is for L7 HTTP(S) load balancers and will
# not attach here.
resource "google_compute_address" "ingress_nginx" {
  name         = "ingress-nginx-ip"
  project      = var.project_id
  region       = var.region     # europe-west1 - the region, not the zone
  address_type = "EXTERNAL"
}