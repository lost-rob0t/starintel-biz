(defpackage #:quasar-auth.host
  (:use #:cl)
  (:nicknames #:starintel.biz.quasar-auth-host)
  (:export
   #:*login-port*
   #:*active-sessions*
   #:start-login-endpoint
   #:stop-login-endpoint
   #:handle-login
   #:activate)
  (:documentation "Runtime bridge between the existing starintel-server auth
and quasar's per-principal WebSocket sessions.

Loaded inside the quasar-server image from init.lisp (trusted operator
code, quasar #58/#73). handle-login authenticates against
starintel-server's /auth/login, applies the starintel-biz entitlement
policy, and registers a per-principal quasar websocket session.

INTERIM status (tracked in starintel-biz): the bridge manages the login
endpoint and session registration. Per-request browser token injection and
session expiry/unregister wait on quasar #71 (per-user session issuance
API) and #72 (WS traversal of the shared origin); until those land, this
bridge is exercised by operators/tests against a running quasar image."))
