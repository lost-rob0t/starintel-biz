# Task prompt: finalize StarIntel OIDC for Quasar

## Context

`https://quasar.starintel.actor` runs the Quasar standalone web edition.
Interim per-user auth (starintel-biz `quasar-auth` plugin) authenticates
against the existing starintel-server `/auth/login` API and registers
per-principal Quasar WebSocket sessions. That plugin is a stopgap by
design. The end state for identity is central StarIntel OIDC.

Authoritative references:

- infra issue #90 — Quasar on the 2-core web host with StarIntel OIDC and
  private backend APIs (the deployment epic)
- infra issue #74 — deploy ZITADEL as the StarIntel identity authority
  (`auth.starintel.actor`, currently a 404 placeholder: ZITADEL is NOT
  deployed yet)
- quasar issue #56 — one codebase, web + Electron, `Sign in with StarIntel`
- quasar issue #71 — per-user session issuance (removes the shared
  local-user token)
- quasar issue #72 — WebSocket traversal of the shared origin
- quasar issue #58/#73 — trusted init.lisp hook surface (the plugin seam
  the interim auth uses)
- `~/starintel/starintel-biz/` — interim plugin (`quasar-auth`,
  `quasar-auth-host`), to be retired or reduced by this work

## Goal

Replace the interim password plugin with Authorization Code + PKCE against
StarIntel ZITADEL, keeping quasar's existing enforcement (per-principal
sessions, workspace authorization, capability checks) unchanged.

## Required work

1. **Deploy ZITADEL (infra #74)**
   - Execute on an infra slice: ZITADEL on its declared host, public issuer
     `https://auth.starintel.actor` through Cloudflare -> ord-edge ->
     mallcop -> web; self-service registration per topology policy.
   - Machine identity for service-to-service calls where required.

2. **Quasar OIDC client (quasar #56, #71)**
   - Browser flow: Authorization Code + PKCE, redirect through
     `auth.starintel.actor`; no password form inside quasar; no second
     user database.
   - On callback, the quasar image verifies the token server-side and
     registers the per-principal websocket session (scopes -> workspaces /
     capabilities mapping moves from starintel-biz entitlement policy to
     OIDC claims mapping, still expressed as init.lisp policy).
   - Suppress the shared `local-user` session (quasar #71 API).
   - Electron packaging uses the system-browser flow with a loopback
     callback; never an embedded password form.

3. **Retire the interim plugin**
   - `starintel-biz` quasar-auth shrinks to the entitlement/claims mapping
     (biz policy stays in biz) or is deleted if fully covered by claims.
   - The CouchDB-backed `/auth/login` path remains for starintel-server's
     own API consumers; quasar simply stops using it.

4. **Gateway posture**
   - Remove the interim mallcop gateway gate for the quasar route when
     browser OIDC is live and verified end-to-end (WebSockets included).
   - Keep operator surfaces (any `*`-workspace grants) behind explicit
     roles.

## Guardrails

- Never place upstream service credentials or the ZITADEL client secret in
  browser JavaScript (PKCE public client, or secret kept server-side).
- Ordinary users must not receive operator authority; test a plain user
  against every operator surface.
- Do not weaken quasar's existing per-connection enforcement while adding
  the OIDC front door.
- No tokens, cookies, or auth headers in telemetry/logs.

## Acceptance (from infra #90)

- `Sign in with StarIntel` works on `quasar.starintel.actor` and grants only
  explicit quasar scopes; operator features require explicit roles.
- WebSockets work through Cloudflare/WAF after sign-in.
- Electron signs in through the system browser.
- Browser bundle contains no service credentials or private endpoints.
- CD rollback restores the previous known-good deployment.
- Interim password plugin no longer answers on the hosted deployment.
