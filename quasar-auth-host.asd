(asdf:defsystem "quasar-auth-host"
  :description "Runtime bridge from starintel-server auth to Quasar sessions."
  :author "StarIntel"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("quasar-auth"
               "quasar-web"
               "clack")
  :serial t
  :pathname "host/"
  :components ((:file "package")
               (:file "bridge"))
  :in-order-to ((test-op (test-op "quasar-auth-host/tests"))))

(asdf:defsystem "quasar-auth-host/tests"
  :description "Integration tests for the Quasar host bridge."
  :author "StarIntel"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("quasar-auth-host")
  :serial t
  :pathname "t/"
  :components ((:file "host-tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :quasar-auth.host.tests :run-tests)))
