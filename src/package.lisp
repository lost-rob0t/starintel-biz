(defpackage #:quasar-auth
  (:use #:cl)
  (:nicknames #:starintel.biz.quasar-auth)
  (:export
   ;; configuration
   #:*starintel-auth-url*
   #:*request-timeout*
   ;; client
   #:auth-session
   #:auth-session-p
   #:auth-session-username
   #:auth-session-principal-type
   #:auth-session-scopes
   #:auth-session-status
   #:auth-session-api-key
   #:auth-session-expires-in
   #:make-auth-session
   #:login-failure
   #:login-failure-p
   #:login-failure-code
   #:login-failure-message
   #:make-request-fn
   #:login
   ;; entitlement policy
   #:*entitlement-policy*
   #:entitlement
   #:entitlement-p
   #:entitlement-principal
   #:entitlement-workspaces
   #:entitlement-capabilities
   #:standard-client-capabilities
   #:operator-capabilities
   #:entitlement-for-session
   ;; session token
   #:mint-session-token
   ;; validation
   #:valid-username-p)
  (:documentation "Interim per-user authentication for the hosted Quasar
runtime, REUSING the StarIntel server's existing auth: this package is a
client of starintel-server's /auth/login (users live in the
starintel-gserver-auth CouchDB database; star.auth owns password hashing and
issuance) plus the StarIntel business entitlement policy mapping
starintel-server scopes to Quasar workspace/capability grants.

This package is deliberately free of quasar runtime dependencies so it is
testable standalone; the runtime bridge lives in the quasar-auth-host
system."))
