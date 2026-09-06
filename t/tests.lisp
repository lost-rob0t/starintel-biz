(defpackage #:quasar-auth.tests
  (:use #:cl #:quasar-auth)
  (:export #:run-tests)
  (:documentation "Plain-runner tests for quasar-auth. No framework, matching
the quasar monorepo test convention: every check signals ERROR with a
description on failure; run-tests prints PASS/FAIL lines and returns T/NIL."))

(in-package #:quasar-auth.tests)

(defparameter *failures* 0)
(defparameter *checks* 0)

(defmacro check-that (description form)
  `(progn
     (incf *checks*)
     (if ,form
         (format t "PASS  ~A~%" ,description)
         (progn
           (incf *failures*)
           (format t "FAIL  ~A~%" ,description)))))

;;; ---- test transport: canned starintel-server responses ----

(defun fake-auth-server (status body)
  "Return a request-fn answering every call with STATUS and parsed BODY."
  (lambda (method path content)
    (declare (ignore method path content))
    (values status (and body (jsown:parse body)))))

(defun ok-login-body (&key (username "alice")
                        (scopes (list "quasar"))
                        (status "active"))
  (jsown:to-json
   (jsown:new-js
     ("api_key" "star_sk_v1_test")
     ("credential" (jsown:new-js ("kind" "api-key")
                                 ("expires_in" 3600)))
     ("user" (jsown:new-js
               ("username" username)
               ("principal_type" "user")
               ("scopes" scopes)
               ("status" status)
               ("created_at" 0)
               ("password_updated_at" 0)
               ("must_change_password" :false))))))

;;; ---- username validation ----

(defun test-usernames ()
  (check-that "valid username accepted" (valid-username-p "alice"))
  (check-that "username with dots/dashes accepted" (valid-username-p "a.li-ce_1"))
  (check-that "empty username rejected" (not (valid-username-p "")))
  (check-that "overlong username rejected" (not (valid-username-p (make-string 33 :initial-element #\a))))
  (check-that "uppercase username rejected" (not (valid-username-p "Alice")))
  (check-that "leading dash rejected" (not (valid-username-p "-alice")))
  (check-that "path separator rejected" (not (valid-username-p "a/b")))
  (check-that "space rejected" (not (valid-username-p "a b"))))

;;; ---- login client ----

(defun test-login-success ()
  (multiple-value-bind (session failure)
      (login "alice" "hunter2" :request-fn (fake-auth-server 200 (ok-login-body)))
    (declare (ignore failure))
    (check-that "login returns a session" (auth-session-p session))
    (check-that "session username" (string= (auth-session-username session) "alice"))
    (check-that "session scopes" (equal (auth-session-scopes session) (list "quasar")))
    (check-that "session status active" (string= (auth-session-status session) "active"))
    (check-that "session api key retained" (string= (auth-session-api-key session) "star_sk_v1_test"))
    (check-that "session expiry captured" (= (auth-session-expires-in session) 3600))))

(defun test-login-rejection ()
  (multiple-value-bind (session failure)
      (login "alice" "wrong" :request-fn (fake-auth-server 401 "{\"error\":\"no\"}"))
    (check-that "401 returns no session" (null session))
    (check-that "401 failure code" (and failure (string= (login-failure-code failure) "invalid_credential"))))
  (multiple-value-bind (session failure)
      (login "alice" "pw" :request-fn (fake-auth-server 503 "{\"error\":\"down\"}"))
    (check-that "503 returns no session" (null session))
    (check-that "503 failure code is auth_unavailable"
                (and failure (string= (login-failure-code failure) "auth_unavailable"))))
  (multiple-value-bind (session failure)
      (login "Bad Name" "pw" :request-fn (fake-auth-server 200 (ok-login-body)))
    (check-that "invalid username rejected locally" (null session))
    (check-that "invalid username failure code" (string= (login-failure-code failure) "invalid_username")))
  (multiple-value-bind (session failure)
      (login "alice" "" :request-fn (fake-auth-server 200 (ok-login-body)))
    (check-that "empty password rejected locally" (null session))
    (check-that "empty password failure code" (string= (login-failure-code failure) "invalid_password"))))

;;; ---- entitlement policy ----

(defun test-entitlements ()
  ;; baseline: scope "quasar" only -> own workspace, standard capabilities
  (multiple-value-bind (ent failure)
      (entitlement-for-session
       (make-auth-session :username "alice" :principal-type "user"
                          :scopes (list "quasar") :status "active"))
    (declare (ignore failure))
    (check-that "basic entitlement granted" (entitlement-p ent))
    (check-that "basic workspaces isolated to own"
                (equal (entitlement-workspaces ent) (list "alice")))
    (check-that "basic capabilities are the standard set"
                (equal (entitlement-capabilities ent)
                       (sort (copy-list standard-client-capabilities) #'string<))))
  ;; shared scope adds the shared default workspace
  (multiple-value-bind (ent failure)
      (entitlement-for-session
       (make-auth-session :username "alice" :principal-type "user"
                          :scopes (list "quasar" "quasar.shared") :status "active"))
    (declare (ignore failure))
    (check-that "shared entitlement includes default"
                (equal (entitlement-workspaces ent) (list "alice" "default"))))
  ;; operator scope grants all workspaces + operator capabilities
  (multiple-value-bind (ent failure)
      (entitlement-for-session
       (make-auth-session :username "root" :principal-type "user"
                          :scopes (list "quasar" "quasar.operator") :status "active"))
    (declare (ignore failure))
    (check-that "operator workspaces are *"
                (equal (entitlement-workspaces ent) (list "*")))
    (check-that "operator capabilities include starlang.load"
                (member "starlang.load" (entitlement-capabilities ent) :test #'string=)))
  ;; no quasar scope -> not entitled
  (multiple-value-bind (ent failure)
      (entitlement-for-session
       (make-auth-session :username "bob" :principal-type "user"
                          :scopes (list "documents.read") :status "active"))
    (check-that "missing scope denies entitlement" (null ent))
    (check-that "missing scope failure code" (string= (login-failure-code failure) "not_entitled")))
  ;; inactive user -> denied
  (multiple-value-bind (ent failure)
      (entitlement-for-session
       (make-auth-session :username "bob" :principal-type "user"
                          :scopes (list "quasar") :status "disabled"))
    (check-that "inactive user denied" (null ent))
    (check-that "inactive user failure code" (string= (login-failure-code failure) "user_inactive")))
  ;; per-user isolation actually isolates
  (let ((a (entitlement-for-session
            (make-auth-session :username "alice" :principal-type "user"
                               :scopes (list "quasar") :status "active")))
        (b (entitlement-for-session
            (make-auth-session :username "bob" :principal-type "user"
                               :scopes (list "quasar") :status "active"))))
    (check-that "alice has no access to bob workspace"
                (not (member "bob" (entitlement-workspaces a) :test #'string=)))))

;;; ---- token minting ----

(defun test-tokens ()
  (let ((one (mint-session-token))
        (two (mint-session-token)))
    (check-that "token length" (>= (length one) 32))
    (check-that "tokens unguessable (distinct)" (not (string= one two)))
    (check-that "tokens use url-safe alphabet"
                (every (lambda (c) (or (char<= #\a c #\z)
                                       (char<= #\A c #\Z)
                                       (char<= #\0 c #\9)))
                       one))))

(defun run-tests ()
  (let ((*failures* 0)
        (*checks* 0)
        (*package* (find-package '#:quasar-auth.tests)))
    (format t "~&;; quasar-auth tests~%")
    (test-usernames)
    (test-login-success)
    (test-login-rejection)
    (test-entitlements)
    (test-tokens)
    (format t "~&;; ~A checks, ~A failures~%" *checks* *failures*)
    (zerop *failures*)))
