;;; Example hosted init.lisp for the quasar-server image.
;;;
;;; Trusted operator configuration (quasar #58). Loaded by quasar's
;;; configured-main before startup. This file never ships to the browser.
;;;
;;; The starintel-biz checkout must be on the image's ASDF source registry
;;; (built into the image or mounted under /run/quasar-biz).

(in-package #:cl-user)

;;; Point quasar-auth at the existing starintel-server auth API on the
;;; ingest host. Service-to-service traffic stays on the private network.
(setf quasar-auth:*starintel-auth-url* "http://10.60.60.20:5000")

;;; Load the starintel-biz bridge and start the private login endpoint.
;;; quasar-auth-host registers per-principal websocket sessions using
;;; quasar's own enforcement (workspaces + capabilities per connection).
(asdf:load-system :quasar-auth-host)
(quasar-auth.host:activate :port 7104 :address "127.0.0.1")

;;; INTERIM, remove when quasar #71 lands:
;;; quasar still registers its shared local-user session at startup. Until
;;; per-user issuance is the default, hosted deployments must treat that
;;; shared token as a deployment secret and rely on the gateway gate, or
;;; patch issuance off via the API quasar #71 will provide.
