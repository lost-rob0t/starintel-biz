(in-package #:quasar-auth)

(defparameter standard-client-capabilities
  '("system.capabilities"
    "workspace.snapshot"
    "workspace.transaction"
    "document.import.begin"
    "document.import.chunk"
    "document.import.commit"
    "document.import.abort"
    "document.list"
    "document.get"
    "document.create"
    "document.update"
    "document.delete"
    "graph.snapshot"
    "graph.workspace.put"
    "graph.workspace.delete"
    "graph.workspace.activate"
    "graph.node.create"
    "graph.node.update"
    "graph.node.delete"
    "graph.edge.create"
    "graph.edge.update"
    "graph.edge.delete"
    "starlang.status")
  "Standard browser-client capability set mirrored from quasar's
+default-capabilities+ (starlang.load excluded). Quasar remains the
enforcement authority.")

(defparameter operator-capabilities
  (append standard-client-capabilities '("starlang.load"))
  "Operator grant: the full standard set plus starlang.load.")

(defstruct entitlement
  "What a login is allowed to do in quasar."
  principal
  (workspaces nil)
  (capabilities nil))

(defparameter *entitlement-policy*
  '((:require-scopes ("quasar"))
    (:grant
     (nil . (:workspaces ("own"))))
    (:grant
     ("quasar.shared" . (:workspaces ("default"))))
    (:grant
     ("quasar.operator" . (:workspaces ("*") :capabilities operator-capabilities))))
  "StarIntel business entitlement policy for hosted quasar.

Data-driven grant table mapping starintel-server scopes to quasar grants.
SEXP form:
  (:require-scopes (\"quasar\"))                      ; mandatory scopes
  (:grant (SCOPE . (:workspaces (...) :capabilities VAR)))

Workspace atoms: \"own\" expands to the user's own workspace (per-user
isolation by default), \"*\" grants every workspace, strings grant one
workspace by name. :capabilities VAR names a capability-set symbol.

Defaults: every user needs scope \"quasar\" and receives ONLY their own
workspace with the standard browser capabilities. \"quasar.shared\" adds the
shared \"default\" workspace. \"quasar.operator\" grants all workspaces and
the operator capability set. Quasar enforces all of this per session.")

(defun entitlement-workspace-p (atom username)
  (case (and (stringp atom) (intern (string-upcase atom) :keyword))
    ((:own) (list username))
    (otherwise (list atom))))

(defun policy-scopes (entry)
  (second entry))

(defun policy-grants (policy)
  (remove-if (lambda (entry) (eq (first entry) :require-scopes)) policy))

(defun required-scopes (policy)
  (let ((require-entry (find :require-scopes policy :key #'first)))
    (and require-entry (policy-scopes require-entry))))

(defun grant-scope (grant)
  ;; entry shape: (:grant (SCOPE . (:workspaces ... :capabilities ...)))
  (first (second grant)))

(defun grant-options (grant)
  (rest (second grant)))

(defun grant-workspaces (grant username)
  (let ((atoms (getf (grant-options grant) :workspaces)))
    (sort
     (remove-duplicates
      (mapcan (lambda (atom) (entitlement-workspace-p atom username))
              atoms)
      :test #'string=)
     #'string<)))

(defun grant-capabilities (grant)
  (let ((name (getf (grant-options grant) :capabilities)))
    (if name
        (copy-list (symbol-value name))
        (copy-list standard-client-capabilities))))

(defun scope-matches-p (scope grant-scope)
  "NIL grant scope matches every login (baseline grant)."
  (or (null grant-scope)
      (member grant-scope scope :test #'string=)))

(defun entitlement-for-session (session)
  "Compute the quasar ENTITLEMENT for one successful starintel-server
login. Returns (VALUES ENTITLEMENT NIL) or (VALUES NIL LOGIN-FAILURE) when
the account is not entitled to quasar (missing required scopes or not an
active user)."
  (let ((policy *entitlement-policy*)
        (scopes (auth-session-scopes session))
        (username (auth-session-username session)))
    (labels ((reject (code message)
               (values nil (make-login-failure :code code :message message))))
      (cond
        ((not (string= (auth-session-status session) "active"))
         (reject "user_inactive" "User is not active."))
        (t
         (let ((missing (remove (lambda (required)
                                  (member required scopes :test #'string=))
                                (required-scopes policy))))
           (declare (ignorable missing))
           (let ((unmet (loop for required in (required-scopes policy)
                              unless (member required scopes :test #'string=)
                                collect required)))
             (cond
               (unmet
                (reject "not_entitled"
                        (format nil "Missing required scope~P: ~{~A~^, ~}"
                                (length unmet) unmet)))
               (t
                (let* ((grants (remove-if-not
                                (lambda (grant)
                                  (scope-matches-p scopes (grant-scope grant)))
                                (policy-grants policy)))
                       (workspaces (sort
                                    (remove-duplicates
                                     (mapcan (lambda (grant)
                                               (grant-workspaces grant username))
                                             grants)
                                     :test #'string=)
                                    #'string<))
                       (workspaces (if (member "*" workspaces :test #'string=)
                                       (list "*")
                                       workspaces))
                       (capabilities (let ((sets (mapcar #'grant-capabilities grants)))
                                       (reduce #'union sets))))
                  (values
                   (make-entitlement
                    :principal username
                    :workspaces workspaces
                    :capabilities (sort (copy-list capabilities) #'string<))
                   nil)))))))))))