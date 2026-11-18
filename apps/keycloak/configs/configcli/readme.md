# keycloak-config-cli — declarative `midworld` realm config

Replaces the **create-only** `KeycloakRealmImport` with **keycloak-config-cli**, which
idempotently reconciles the realm *config* from Git via the Keycloak admin API. This is
the prerequisite that lets the GitLab **confidential `gitlab` client** (and the
currently-imperative flux-web client / groups scope / flux-admins group) be managed
declaratively. Activated 2026-08-13 — see "Activation / migration steps" below for
what's done vs still pending (dropping the old KeycloakRealmImport).

Background + the decision: `../../docs/adr` and the memory
`reference-keycloak-config-management` (config vs data boundary; DROP the import CR).

## Files

```
config-cli-job.yaml          CronJob (+ ad-hoc Job) that runs config-cli
admin-secret-sealed.yaml     admin creds for the admin API (placeholder — SEAL)
kustomization.yaml           builds the realm ConfigMap from realm-config/*
realm-config/
  10-midworld-base.json          <- FROZEN realm: settings + scopes + built-in clients only
  15-stigman-client.yaml         stigman public client (STIG Manager SSO)
  20-groups-scope.yaml           groups client scope + group-membership mapper
  30-flux-web-client.yaml        flux-web confidential client (Flux UI SSO)
  40-flux-admins-group.yaml      flux-admins group (membership stays out of Git)
  50-gitlab-client.yaml          gitlab confidential client (GitLab SSO)
```

The `20`–`50` fragments were **recovered from the live realm** (UUIDs stripped,
references by name). They make declarative what was created imperatively, plus the new
`gitlab` client.

## Mental model (read this first)

**You edit a config file in Git; config-cli makes Keycloak match it.** It reconciles
(adds/updates what's described, doesn't wipe the realm). With
`IMPORT_REMOTESTATE_ENABLED=true` it purges **only resources config-cli manages** — so
**users, group memberships, and passwords (DATA) are left untouched** because they are
not in the config files. Config in Git; data stays live.

## Workflow — adding/changing realm config (so you NEVER hand-edit the big file)

The base realm file (`10-midworld-base.json`) is **FROZEN — do not hand-edit it.** It was
extracted from the existing `KeycloakRealmImport` (`spec.realm`, no users), then the
`stigman` client was lifted OUT into its own fragment (`15-`). The base now holds only the
realm settings, the 23 clientScopes (incl. `stig-manager:*`, referenced by name from the
stigman fragment), and Keycloak's 6 built-in clients. **Every app client and every
addition is a fragment** (`15-`, `30-`, `50-` clients; `20-` scope; `40-` group), never an
edit to the base. Which fragment path depends on the change:

1. **Client using only built-in scopes** (e.g. `gitlab`): write a small client fragment
   that lists `defaultClientScopes` BY NAME (`openid`, `profile`, `email`). Done. (See
   `50-gitlab-client.yaml`.)

2. **Client needing a custom scope + mapper** (e.g. flux-web + `groups`): two small
   fragments — a scope fragment with the mapper **nested inside it**
   (`20-groups-scope.yaml`), and a client fragment that names the scope
   (`30-flux-web-client.yaml`). All references by name.

3. **Groups / role-mappings** (e.g. `flux-admins`): a small group fragment
   (`40-flux-admins-group.yaml`). Names only. Membership is data — not here.

4. **Anything you can't confidently hand-write** (fiddly mapper, IdP, auth flow):
   - Build it in the **Keycloak admin UI** (it validates + wires IDs for you).
   - **Partial-export** the realm (Realm Settings → Action → Partial export, or
     `kcadm get realms/midworld`).
   - **Lift just the new slice** (the one client/scope) into a fragment file.
   - **STRIP all `id` / UUID fields** and any `clientScopeId`/`containerId` ID refs —
     reference by NAME instead. (Stale UUIDs from an export are the #1 cause of broken
     imports.)
   - Commit the fragment. config-cli reconciles it.

**The rule:** fragments reference other objects **by name** and keep sub-objects
(mappers) **nested inside** their parent. As long as that holds, fragments stay small and
safe. Cross-object references by UUID = don't hand-write; use the GUI-export-harvest loop.

## Client secrets (important)

Confidential clients have secrets. config-cli can set a client's `secret` from the config
or leave Keycloak's generated one. Keep these consistent with the sealed secrets the apps
use:
- **flux-web**: secret already sealed at
  `infrastructure/controllers/flux-operator/flux-web-client-sealed.yaml` and injected to the operator.
  Don't let config-cli rotate it out from under the running Flux UI — either omit `secret`
  (leave Keycloak's existing value) or set it to the same sealed value.
- **gitlab**: must match the GitLab-side `gitlab-oidc` provider secret
  (`_pending/gitlab/base/gitlab-oidc-secret-sealed.yaml`). Decide one source of truth and
  seal both sides to it.
Do NOT put plaintext client secrets in the fragment files committed to Git. If config-cli
must set a secret, inject it via `IMPORT_VARSUBSTITUTION` from an env var sourced from a
sealed secret.

## Activation / migration steps

1. **Frozen base realm — DONE.** `realm-config/10-midworld-base.json` was extracted from
   `infrastructure/configs/keycloak/realm-midworld.yaml` (`spec.realm`), validated (6
   built-in clients, 23 scopes, no users — `stigman` lifted into `15-stigman-client.yaml`),
   and wired into `kustomization.yaml`.
   No action needed unless the live realm has drifted since extraction — if so, re-export
   and replace it. (Optionally re-export from the live realm at activation to capture any
   base-level drift, but keep flux-web/groups/flux-admins as fragments, not in the base.)
2. **Seal `keycloak-config-cli-admin`** (see the placeholder for the command).
3. **Pick a config-cli image** compatible with the running Keycloak (26.6.3): tag
   `<cli>-<kc>`, e.g. `6.5.1-26.x` — **verify a KC26 build exists** (the 6.5.1 release
   assets seen at authoring stopped at KC25; confirm before relying on it).
4. **Move this dir** into `infrastructure/configs/keycloak-config-cli/` and add it to
   `infrastructure/configs/kustomization.yaml`.
5. **Run once** (the CronJob, or `kubectl create job -n sso
   --from=cronjob/keycloak-config-cli kcc-initial`) and check the log: realm intact, the
   four additions present, **the `admin` user + its memberships UNTOUCHED**, Flux UI SSO +
   stigman login still work.
6. **Drop the KeycloakRealmImport**: remove `realm-midworld.yaml` from
   `infrastructure/configs/keycloak/kustomization.yaml` (and the file) so there's a single
   source of truth. config-cli now owns the realm.

## Verify items
- KC26-compatible config-cli image tag exists.
- config-cli multi-file merge applies all fragments to the one `midworld` realm in one run
  (order 10→50; base must define the realm before fragments add to it).
- flux-web / gitlab client secrets stay consistent with their sealed values (no surprise
  rotation).
