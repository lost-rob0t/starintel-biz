# starintel-biz

StarIntel hosted business layer. Deployment customization for the hosted
Quasar runtime (`quasar.starintel.actor`) lives here as trusted plugins,
loaded through Quasar's `init.lisp` hook (quasar #58/#73), never inside
Quasar core and never shipped to the browser.

Current plugin:

- **quasar-auth** — interim per-user authentication without OIDC that
  REUSES the existing StarIntel server auth: users and password hashing
  stay in starintel-server (`star.auth`, `starintel-gserver-auth` CouchDB
  database); the plugin is a client of the existing `POST /auth/login`
  API and adds the StarIntel business entitlement policy mapping
  starintel-server scopes to Quasar workspace/capability grants. A
  successful, entitled login registers a per-principal Quasar WebSocket
  session via `quasar.ws:register-websocket-session`; quasar's own
  enforcement (per-workspace authorization, capability checks, origin/
  rate/size limits) does the gating.

The end state is StarIntel OIDC (quasar #56, infra #74/#90) — see
`docs/prompts/oidc-finalization.md`.

Quasar's enforcement layer (per-principal sessions, per-workspace
authorization, capability checks) already supports multiple users; the
issuance gaps are tracked on quasar: #71 (per-user session issuance),
#72 (WebSocket traversal of the shared origin), #73 (init hook surface).

## Layout

```
quasar-auth.asd        auth client + entitlement policy (no quasar deps)
src/                   quasar-auth sources
t/                     quasar-auth tests (plain runner, no framework)
host/                  quasar-auth-host bridge, loaded inside the quasar image
example/init.lisp      hosted init example
docs/prompts/          follow-up task prompts
```

## Auth flow

```text
browser/operator        quasar image (init.lisp)        starintel-server
      |                        |                              |
      |  POST /biz/auth/login  |                              |
      |----------------------->|   POST /auth/login           |
      |                        |----------------------------->|
      |                        |   user + scopes + api-key    |
      |                        |<-----------------------------|
      |                        |  entitlement policy          |
      |                        |  (scopes -> workspaces/caps) |
      |  quasar WS session     |                              |
      |<-----------------------|                              |
      |  connect ws + token    |                              |
      |----------------------->| quasar enforces per-command  |
```

- starintel-server owns users, password hashing, and issuance.
- The plugin owns only the biz entitlement policy (scope -> quasar
  workspace/capability grants) and session registration.
- The starintel-server `api_key` never reaches the browser; the browser
  receives only the minted quasar WebSocket session token.

## Entitlement policy

`*entitlement-policy*` maps starintel-server scopes to quasar grants:

- scope `quasar` (required): the user's own isolated workspace + the
  standard browser capability set
- scope `quasar.shared`: adds the shared `default` workspace
- scope `quasar.operator`: all workspaces + operator capabilities
  (`starlang.load` included)
- accounts without the `quasar` scope, or not active, are not entitled

## Tests

```
sbcl --noinform --non-interactive \
  --eval '(ql:quickload (list :dexador :ironclad :babel :jsown :quri) :silent t)' \
  --eval '(push #P"/path/to/starintel-biz/" asdf:*central-registry*)' \
  --eval '(asdf:load-system :quasar-auth)' \
  --eval '(asdf:test-system :quasar-auth)'
```

## Security model

- The plugin is trusted operator code, same trust class as init.lisp.
- Identity stays in one place: starintel-server's user database. No second
  password database, no credential duplication.
- The plugin performs no password handling at all; it forwards to
  starintel-server's `/auth/login` and never stores password material.
- The starintel-server api-key stays server-side; only the minted quasar
  session token reaches the browser.
- Quasar's websocket server enforces workspaces/capabilities per
  connection; the policy table only shapes issuance.

## License

AGPL-3.0-only, matching Quasar.