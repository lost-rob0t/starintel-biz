(asdf:defsystem "quasar-auth"
  :description "StarIntel hosted business layer: interim per-user authentication for Quasar, reusing the existing starintel-server auth API."
  :author "StarIntel"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("babel"
               "dexador"
               "ironclad"
               "jsown"
               "quri")
  :serial t
  :pathname "src/"
  :components ((:file "package")
               (:file "client")
               (:file "entitlement")
               (:file "token"))
  :in-order-to ((test-op (test-op "quasar-auth-tests"))))

(asdf:defsystem "quasar-auth-tests"
  :description "Tests for quasar-auth."
  :author "StarIntel"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("quasar-auth")
  :serial t
  :pathname "t/"
  :components ((:file "tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :quasar-auth.tests :run-tests)))

(asdf:defsystem "quasar-auth-host"
  :description "Runtime bridge: registers per-principal quasar WebSocket sessions for starintel-server-authenticated users. Loaded inside the quasar-server image via init.lisp."
  :author "StarIntel"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("quasar-auth"
               "clack")
  :serial t
  :pathname "host/"
  :components ((:file "package")
               (:file "bridge")))