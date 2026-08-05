# Realm reference — documentation, not truth

`homelab-realm.yaml` describes the `homelab` realm as it was first created: the
`argocd` client, both groups, and the group-membership mapper Argo CD's RBAC
depends on.

**Nothing applies it, and nothing keeps it accurate.** The Argo CD Application
for Keycloak points at `../manifests`, so this directory is inert. Treat it as a
starting-point snapshot, not as a description of the live realm.

## Realm configuration is managed by hand, on purpose

Realms, clients, mappers and groups are edited in the Keycloak admin console at
https://auth.koufan.dev. That is a deliberate choice, made after the declarative
options were tried:

- `KeycloakOIDCClient` required the Experimental `client-admin-api:v2` feature
  and threw a `NullPointerException` inside the operator's own admin client.
- Realm import runs with `--override=false`. Keycloak's documentation is
  explicit: *"If a realm already exists in the server, the import operation is
  skipped."* Changing anything meant deleting the realm.
- `spec.placeholders` injects the environment variable correctly, but the
  operator never sets `keycloak.migration.replace-placeholders`, so substitution
  silently does not happen and Keycloak generates a random client secret
  instead.

The operator was then removed entirely — it requested 300m CPU, double what
Keycloak itself asks for, on a cluster with none to spare.

## The consequence, stated plainly

This is the one place where this repository stops being the source of truth.

Everything else here — the cluster, Argo CD, ingress-nginx, cert-manager, ESO,
Keycloak's *deployment* — is reconstructible from git. Keycloak's *contents* are
not. Realms, clients, groups, mappers and users exist only in Postgres, on a
zonal disk, with `persistentVolumeClaimRetentionPolicy: whenDeleted: Delete`.

Concretely: the destroy-and-recreate test in [ROADMAP.md](../../../../docs/ROADMAP.md)
would bring the cluster back with Keycloak running and **empty**. Argo CD login
would break until the realm and client were recreated by hand.

If that ever matters, the cheapest mitigations in order of effort:

1. Export the realm periodically (`kcadm.sh get realms/homelab` or a
   `kc.sh export` Job) and commit the result here, so this file stops being a
   snapshot and starts being current.
2. Back up the Postgres volume — a `pg_dump` CronJob to GCS, which also covers
   users and is on the roadmap for other reasons.
3. Adopt [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli),
   which applies realm config idempotently and would make this file
   authoritative again.

Until one of those exists, "recoverable from this repo" has an asterisk, and the
asterisk is Keycloak.
