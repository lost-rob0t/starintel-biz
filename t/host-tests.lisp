(defpackage #:quasar-auth.host.tests
  (:use #:cl)
  (:export #:run-tests))

(in-package #:quasar-auth.host.tests)

(defvar *checks* 0)
(defvar *failures* 0)

(defmacro check-that (description form)
  `(progn
     (incf *checks*)
     (if ,form
         (format t "PASS  ~A~%" ,description)
         (progn
           (incf *failures*)
           (format t "FAIL  ~A~%" ,description)))))

(defun fake-auth-transport (method path content)
  (check-that "bridge posts to the existing auth endpoint"
              (and (eq method :post) (string= path "/auth/login")))
  (let ((request (jsown:parse content)))
    (check-that "bridge forwards the submitted identity"
                (and (string= (jsown:val request "username") "alice")
                     (stringp (jsown:val request "password")))))
  (values
   200
   (jsown:new-js
     ("api_key" "test-server-key")
     ("credential" (jsown:new-js ("kind" "api-key") ("expires_in" 3600)))
     ("user" (jsown:new-js
               ("username" "alice")
               ("principal_type" "user")
               ("scopes" (list "quasar"))
               ("status" "active"))))))

(defun response-json (response)
  (jsown:parse (first (third response))))

(defun test-handle-login-registers-real-session ()
  (let* ((plane (quasar.control-plane:make-control-plane))
         (server (quasar.ws:make-websocket-server plane))
         (quasar.app:*websocket-server* server))
    (clrhash quasar-auth.host:*active-sessions*)
    (let* ((body (jsown:new-js
                   ("username" "alice")
                   ("password" (make-string 12 :initial-element #\x))))
           (response (quasar-auth.host:handle-login
                      body :request-fn #'fake-auth-transport))
           (json (response-json response))
           (token (jsown:val json "token"))
           (session (gethash token
                             (quasar.ws::websocket-server-sessions server))))
      (check-that "successful login returns HTTP 200" (= (first response) 200))
      (check-that "response returns a fresh Quasar token" (stringp token))
      (check-that "server credential is not returned"
                  (null (search "test-server-key" (first (third response)))))
      (check-that "token is registered in the real websocket server" session)
      (check-that "registered principal comes from starintel-server"
                  (string= (getf session :principal) "alice"))
      (check-that "registered workspace is per-principal"
                  (equal (getf session :workspaces) '("alice")))
      (check-that "registered authority records its issuer"
                  (eq (getf session :authority-kind) :starintel-server))
      (check-that "operator bookkeeping points at the registered token"
                  (string= (gethash "alice" quasar-auth.host:*active-sessions*)
                           token)))))

(defun test-invalid-body-stops-before-auth ()
  (let ((called nil))
    (let ((response
            (quasar-auth.host:handle-login
             nil
             :request-fn (lambda (&rest arguments)
                           (declare (ignore arguments))
                           (setf called t)))))
      (check-that "missing JSON body returns HTTP 400" (= (first response) 400))
      (check-that "missing JSON body does not contact auth" (not called)))))

(defun run-tests ()
  (let ((*checks* 0)
        (*failures* 0))
    (format t "~&;; quasar-auth-host tests~%")
    (test-handle-login-registers-real-session)
    (test-invalid-body-stops-before-auth)
    (format t "~&;; ~A checks, ~A failures~%" *checks* *failures*)
    (zerop *failures*)))
