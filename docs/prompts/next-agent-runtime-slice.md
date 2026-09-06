# Task: finish the hosted Quasar runtime slice — CL runner on web.star.intel, gated per user via the starintel-biz auth plugin

You are picking up an in-flight, partially-complete slice. The static web
edition is already deployed; this slice adds the Common Lisp runtime
runner and per-user gating WITHOUT OIDC.

## State you inherit (verified, do not re-derive)

### Deployed and verified (do not redo)

- `https://quasar.starintel.actor` serves the Quasar **standalone web
  edition**: the Vite production bundle (`web-dist`) from the quasar
  monorepo, served by a sandboxed miniserve unit (`quasar-web.service`,
  loopback 7101) on `web.star.intel` (10.60.60.15, NixOS LXC), routed
  Cloudflare -> ord-edge -> mallcop -> web Caddy.
- Infra branch `feat/quasar-web-deploy` (PR
  https://git.starintel.actor/starintel-labs/starintel-infra/pulls/106,
  base `feat/main-site-deploy`), commits `e476a28` + `aa8a080`.
- Quasar branch `feat/web-deploy` (PR
  https://git.starintel.actor/nsaspy/quasar/pulls/70), commits `5f2cce2`,
  `e47af84`, `7c07e95` (git+https pin for starintel_doc; `packages.web-dist`).
- Production verified with screenshots (all SPA routes 200, assets/sw/manifest
  200, starintel.actor apex unaffected). The web host was deployed via the
  canonical per-node deploy-rs procedure (build -> nix copy through the
  proxmox jump -> `deploy .#web` -> verify /run/current-system).

### CI gotcha already fixed once — check it

- Forgejo Actions on infra failed in ~11s (run 43/44) because the `quasar`
  flake input used `git+ssh` and the `nixos` runner has no deploy key for
  `nsaspy/quasar`. `nsaspy/quasar` is PUBLIC; fixed by switching to
  `git+https` in `aa8a080`. **First action: verify run for `aa8a080` is
  green** (`tea` or the Forgejo API). If red, fix forward on the same PR.

### Quasar multi-user reality (the answer to "does quasar allow many users/writers?")

- Enforcement layer: YES, fully multi-principal. Sessions map token ->
  (principal, authority-kind, workspaces, capabilities)
  (`quasar.ws:register-websocket-session`); every command validates the
  workspace against the connection's authorized list (`security.forbidden`)
  and checks capabilities; unknown tokens are rejected 401 at the WS
  handshake; origin allowlist + rate/size limits + audit records exist.
- Issuance layer: NO, single-user. `quasar.app:start` registers ONE shared
  session (principal `local-user`, workspace `default`) and injects that one
  token into every served page (`quasar.ui:inject-session-token`). The
  frontend hardcodes WS port `:8081` (`frontend/src/control-plane/client.ts`
  `defaultWebSocketUrl`). `start` never plumbs `allowed-origins`.
- Core gaps are TRACKED, do not fix them ad-hoc inside quasar unless the
  issue workflow says so:
  - quasar #71 — per-user session issuance, session unregister, suppress
    shared token, expose allowed-origins
  - quasar #72 — WS traversal through the reverse proxy (meta-tag endpoint)
  - quasar #73 — init.lisp trusted-plugin hook surface (session-created,
    http-request middleware)

### starintel-biz (the biz plugin repo) — bootstrapped, UNCOMMITTED, UNPUSHED

`~/starintel/starintel-biz` (forge `starintel-labs/starintel-biz`, currently
empty on the forge, local has uncommitted work):

- `quasar-auth` ASDF system (pure, no quasar deps): a client of the
  EXISTING starintel-server auth — `POST /auth/login` on the ingest host
  (docker compose `starintel`, HTTP API port 5000; users live in the
  `starintel-gserver-auth` CouchDB DB; `star.auth` owns hashing/issuance,
  returns `api_key` + user + scopes). Includes the biz entitlement policy
  `*entitlement-policy*` mapping starintel-server scopes to quasar grants:
  `quasar` (required) -> own workspace + standard browser capabilities;
  `quasar.shared` -> adds `default`; `quasar.operator` -> `*` + operator
  capabilities (incl. `starlang.load`). Session token minting via ironclad.
- `quasar-auth-host` ASDF system (bridge for the quasar image): clack login
  endpoint `POST /biz/auth/login` (private port 7104) that logs in via the
  client, applies entitlements, registers a per-principal
  `quasar.ws:register-websocket-session` with
  `:authority-kind :starintel-server`, and returns ONLY the minted WS
  session token (the starintel-server api_key stays server-side).
- `example/init.lisp`, `docs/prompts/oidc-finalization.md`, README.
- Tests: plain-runner convention (like quasar), **36/36 pass** locally:
  ```
  SSL=$(nix eval --raw nixpkgs#openssl.out)
  export CL_SOURCE_REGISTRY="(:source-registry (:tree \"$HOME/quicklisp/local-projects/\") (:tree \"$HOME/quicklisp/dists/quicklisp/software/\") (:directory \"$HOME/starintel/starintel-biz/\") :ignore-inherited-configuration)"
  LD_LIBRARY_PATH="$SSL/lib" sbcl --noinform --non-interactive \
    --eval '(ql:quickload (list :dexador :ironclad :babel :jsown :quri :clack) :silent t)' \
    --eval '(asdf:load-system :quasar-auth)' \
    --eval '(asdf:test-system :quasar-auth)'
  ```
  (The default CL source registry on this workstation pulls a broken lem
  qlot cl+ssl; always pin CL_SOURCE_REGISTRY and LD_LIBRARY_PATH as above.)
- **KNOWN BUG, unfixed**: `asdf:load-system :quasar-auth-host` inside the
  quasar dev shell (`nix develop` in `~/starintel/quasar`, CL_SOURCE_REGISTRY
  including `~/starintel/tek9/` and quasar `systems/`) fails with an
  unhandled condition. Most likely cause: `host/bridge.lisp` reads symbols
  in the `quasar.ws` / `quasar.app` packages which do not exist unless
  `quasar-web` is loaded, and `quasar-auth-host.asd` does not depend on
  `quasar-web`. Either add `"quasar-web"` to its `:depends-on` (preferred:
  the bridge is designed to live inside the quasar image) or resolve
  symbols lazily via find-symbol at runtime. Diagnose the actual condition
  first — do not guess.

## Your tasks, in order

1. **Verify infra PR #106 CI is green** at `aa8a080`. Fix forward if not.
   Do not merge without green CI.

2. **Finish and ship starintel-biz** (worktree per the git-worktrees skill,
   primary checkout stays clean):
   - Fix the `quasar-auth-host` load bug described above; prove the bridge
     compiles and `handle-login` round-trips inside the quasar dev shell
     against a fake auth transport and a real `quasar.ws:websocket-server`
     instance (there are existing websocket-auth tests in
     quasar `control-plane/tests/autodig-websocket-auth-tests.lisp` to
     crib the harness from).
   - Commit with sensible messages, push to
     `starintel-labs/starintel-biz` (origin = the forge; a `github` remote
     exists too), open a tracking issue on the forge describing the plugin,
     its interim status, and its dependency on quasar #71/#72/#73.
   - Do NOT put secrets, tokens, or credentials in the repo.

3. **Deploy the Common Lisp runtime runner on the web host, gated per user
   (interim gate, no OIDC)**:
   - Package `quasar-server` with Nix following the in-family precedent:
     `sbcl.buildASDFSystem` per dependency (see
     `~/starintel/starintel-server/flake.nix` and
     `~/starintel/starintel-webhooks/flake.nix` — pinned revs, hashes,
     native libs) plus a saved image (`save-lisp-and-die` toplevel
     `quasar.app:main`, mirror `scripts/run-production`'s dependency list:
     babel bordeaux-threads clack clog dexador jsown quri sento tek9
     websocket-driver + quasar systems; native libs openssl rabbitmq-c
     libffi sqlite lmdb; tek9 from `starintel-labs/tek9` on the forge).
     Add the package to the quasar flake on a NEW branch off
     `feat/web-deploy` (worktree). Watch out: runtime image + plugin need
     `example/init.lisp`-style hosted init —
     `quasar.config:safe-load-init` honors `QUASAR_INIT_FILE`.
   - Infra (worktree, branch off `feat/quasar-web-deploy`): add the runtime
     service module (systemd unit, sandboxed like `quasar-web.service`,
     ports per the topology's inventory-owned 7101-7106 block, CLOG static
     + WS, persistent state dir under /var/lib, `QUASAR_INIT_FILE` pointing
     at the deployed init that activates `quasar-auth-host` and sets
     `quasar-auth:*starintel-auth-url*` at the ingest host's port 5000),
     path-split routing on the quasar vhost at the web Caddy
     (`/biz/auth/login` -> bridge port, `/control-ws`-style path -> WS port
     — but see quasar #72: the stock frontend cannot use it yet; routing
     can land ready for #72 without exposing a broken feature), and the
     **mallcop gatewayAuth gate** on the whole quasar route until per-user
     auth is live end-to-end: `gatewayAuth = "quasar"` in the service entry
     renders `import /var/lib/starintel/secrets/auth-quasar` — a per-user
     basic-auth secret file the deploy script must install to the tunnel
     host (extend `install_nixos_runtime_material`'s `tunnel` case; the
     operator secret dir is `~/.config/starinfra/`). bcrypt hashes via
     `caddy hash-password`. NEVER commit the credential file.
   - Because quasar #71/#72 are open, the runtime's shared `local-user`
     session must be treated as a deployment secret: the gatewayAuth gate
     is what makes the shared-token era survivable. Say this in the PR;
     do not pretend it is per-user isolation.
   - Extend `prolog/quasar_deployment.pl` (mirror the website/quasar gate):
     runtime unit active+boot-start, private ports not in the firewall,
     gatewayAuth set on the quasar route, bridge unit present. `nix flake
     check` must pass.
   - Deploy exactly the canonical per-node procedure used before (build ->
     nix copy -> `deploy .#web` and any tunnel-host material step -> verify
     /run/current-system). If the tunnel host changes, deploy it the same
     per-node way. Screenshots before/after; verify the static edition and
     starintel.actor are unharmed.

4. **Wire the biz plugin into the runtime's hosted init** (the init file is
   generated by infra into the service state dir, or shipped in the package
   — pick one, document it): activate the bridge, point it at starintel
   auth, and prove with curl that a real CouchDB user login on
   `/biz/auth/login` returns a token that opens a real WS session at the
   runtime (integration test through the loopback, not through the public
   internet — #72 blocks the public path).

5. **Open the follow-up issues** if not already present:
   - starintel-biz: plugin tracking issue (see task 2).
   - infra: update issue #90 with the runtime-slice state and remaining
     OIDC work (the full OIDC prompt already exists at
     `starintel-biz/docs/prompts/oidc-finalization.md` — do not duplicate
     it, link it).

## Guardrails

- The identity store stays starintel-server's CouchDB users. NO second user
  database, no password handling in the plugin, no credentials in browser
  bundles, no secrets in git/logs/screenshots.
- Do not implement OIDC in this slice (that is the separate finalized prompt)
  and do not redesign quasar's auth in core — quasar #71/#72/#73 own the
  core changes.
- Do not dirty primary checkouts: worktrees only (git-worktrees skill).
- Use the prolog-verification skill: `prolog-verify init --task <id>` in each
  worktree, record real commands via `prolog-verify observe --`, add
  task-specific invariants, `prolog-verify check` before claiming done.
  Never assert self-certifying success facts.
- Do not change unrelated infrastructure; do not redeploy every host — the
  per-node deploy-rs procedure is the established narrow mechanism.
- Local-only work: no web research required.
- Tests are mandatory: quasar-auth tests, the bridge harness, `nix flake
  check`, `nix build` of the new packages, and production verification with
  screenshots after deploy. Do not stop at "deploy triggered".

## Final report

Return: repos/worktrees/branches used, commits, PR links, CI status, what
ships (runtime package, module, routes, gate), what is deliberately
deferred (per-user public issuance = quasar #71/#72/#73 + the OIDC prompt),
test evidence (prolog-verify facts + check result), production verification
(curl + screenshots of the gated route and the static edition), and any
known-broken or interim behaviors explicitly labeled as such.