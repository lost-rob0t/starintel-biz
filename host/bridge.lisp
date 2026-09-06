(in-package #:quasar-auth.host)

(defparameter *login-port* 7104
  "Private clack port for POST /biz/auth/login. Loopback by default; the
shared web origin's reverse proxy is the only intended ingress.")

(defparameter *handler* nil
  "Active clack handler when the login endpoint is running.")

(defparameter *active-sessions* (make-hash-table :test #'equal)
  "Principal -> quasar websocket session token. Bookkeeping for operators;
quasar's websocket server owns the authoritative session table.")

(defparameter *ws-server-locator* 'quasar.app:*websocket-server*
  "Symbol naming quasar's global websocket server. Parameterized so tests
can substitute a fake without loading the full quasar image.")

(defun ws-server ()
  (symbol-value *ws-server-locator*))

(defun json-response (status object)
  `(,status
    (:content-type "application/json"
     :cache-control "no-store")
    (,(jsown:to-json object))))

(defun error-response (status code message)
  (json-response status (jsown:new-js ("error" code) ("message" message))))

(defun read-json-body (stream)
  "Read the request body and parse it as a JSON object; NIL when absent."
  (let ((data (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for byte = (read-byte stream nil nil)
          while byte
          do (vector-push-extend byte data))
    (when (plusp (length data))
      (ignore-errors
        (jsown:parse (babel:octets-to-string data))))))

(defun register-session (entitlement)
  "Register a quasar websocket session for ENTITLEMENT and return the
minted token. Quasar enforces workspaces/capabilities per connection."
  (let ((token (quasar-auth:mint-session-token)))
    (quasar.ws:register-websocket-session
     (ws-server)
     token
     (quasar-auth:entitlement-principal entitlement)
     (quasar-auth:entitlement-workspaces entitlement)
     :capabilities (quasar-auth:entitlement-capabilities entitlement)
     :authority-kind :starintel-server)
    (setf (gethash (quasar-auth:entitlement-principal entitlement) *active-sessions*)
          token)
    token))

(defun handle-login (body &key (request-fn (quasar-auth:make-request-fn)))
  "Core handler: BODY is a parsed {\"username\",\"password\"} JSON object.

Returns a clack-style response. On success the JSON carries ONLY the minted
quasar session token; the starintel-server api_key stays server-side."
  (flet ((bad (code message)
           (error-response 400 code message)))
    (unless body
      (return-from handle-login
        (bad "invalid_request" "JSON body required.")))
    (let ((username (ignore-errors (jsown:val body "username")))
          (password (ignore-errors (jsown:val body "password"))))
      (unless (and (stringp username) (stringp password))
        (return-from handle-login
          (bad "invalid_request" "username and password strings required.")))
      (multiple-value-bind (session failure)
          (quasar-auth:login username password :request-fn request-fn)
        (cond
          ((null session)
           (error-response 401
                           (quasar-auth:login-failure-code failure)
                           (quasar-auth:login-failure-message failure)))
          (t
           (multiple-value-bind (entitlement failure)
               (quasar-auth:entitlement-for-session session)
             (cond
               ((null entitlement)
                (error-response 403
                                (quasar-auth:login-failure-code failure)
                                (quasar-auth:login-failure-message failure)))
               (t
                 (let ((token (register-session entitlement)))
                  (json-response
                   200
                   (jsown:new-js
                     ("token" token)
                     ("principal" (quasar-auth:entitlement-principal entitlement))
                     ("workspaces" (quasar-auth:entitlement-workspaces entitlement))))))))))))))

(defun login-app (env)
  "Clack app: POST /biz/auth/login -> handle-login; everything else 404."
  (let ((path (getf env :path-info))
        (method (getf env :request-method)))
    (cond
      ((and (string= path "/biz/auth/login") (eq method :post))
       (handle-login (read-json-body (getf env :raw-body))))
      (t '(404 (:content-type "text/plain") ("not found"))))))

(defun start-login-endpoint (&key (port *login-port*) (address "127.0.0.1"))
  "Start the private login endpoint."
  (when *handler*
    (error "quasar-auth-host login endpoint already running."))
  (setf *handler* (clack:clackup #'login-app
                                 :server :hunchentoot
                                 :address address
                                 :port port
                                 :use-thread t))
  (format *error-output* "~&[quasar-auth-host] login endpoint on ~A:~A~%"
          address port)
  *handler*)

(defun stop-login-endpoint ()
  (when *handler*
    (clack:stop *handler*)
    (setf *handler* nil)
    t))

(defun activate (&key (port *login-port*) (address "127.0.0.1"))
  "init.lisp entrypoint: start the login endpoint inside the running
quasar-server image. Requires the quasar image to be started with its
websocket server up (quasar.app:*websocket-server*)."
  (start-login-endpoint :port port :address address)
  t)
