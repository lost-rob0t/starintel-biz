(in-package #:quasar-auth)

(defparameter *starintel-auth-url* nil
  "Base URL of the existing starintel-server auth API, for example
\"http://ingest.star.intel:5000\". When NIL the environment is consulted at
login time (STARINTEL_AUTH_URL, then COUCHDB-independent default).")

(defparameter *request-timeout* 10
  "Per-request timeout, seconds.")

(defun environment-value (name)
  (let ((value (uiop:getenv name)))
    (and value (plusp (length value)) value)))

(defun default-auth-url ()
  (or *starintel-auth-url*
      (environment-value "STARINTEL_AUTH_URL")
      "http://127.0.0.1:5000"))

(defstruct auth-session
  "Result of one successful starintel-server login.

API-KEY is starintel-server's own expiring session key (never shown to the
browser); the quasar WebSocket session token is minted separately by the
host bridge."
  username
  principal-type
  (scopes nil)
  status
  api-key
  (expires-in nil))

(defstruct login-failure
  "A rejected login: code mirrors starintel-server's error codes."
  code
  message)

(defun make-request-fn (&key (base-url (default-auth-url)))
  "Return the production HTTP transport: (lambda (method path content)
(values status parsed-json-or-nil)).

CONTENT is a JSON string or NIL; PATH is relative to BASE-URL. Transport
errors signal; starintel-server status codes come back as integers."
  (lambda (method path content)
    (multiple-value-bind (body status)
        (dexador:request
         (quri:render-uri (quri:merge-uris (quri:uri path) (quri:uri base-url)))
         :method method
         :content (and content (babel:string-to-octets content))
         :content-type "application/json"
         :connect-timeout 5
         :read-timeout *request-timeout*
         :keep-alive nil)
      (let ((text (and body (babel:octets-to-string body))))
        (values
         status
         (and text (plusp (length text))
              (ignore-errors (jsown:parse text))))))))

(defun valid-username-p (username)
  "1..32 chars of [a-z0-9._-] starting alphanumeric; restricted so the value
is safe in principals, quasar workspaces, and audit records without
escaping. starintel-server's own normalization remains the authority."
  (and (stringp username)
       (<= 1 (length username) 32)
       (every (lambda (char)
                (or (char<= #\a char #\z)
                    (char<= #\0 char #\9)
                    (member char '(#\. #\_ #\-))))
              username)
       (let ((first (char username 0)))
         (or (char<= #\a first #\z)
             (char<= #\0 first #\9)))))

(defun login (username password &key (request-fn (make-request-fn)))
  "Authenticate USERNAME/PASSWORD against the existing starintel-server
auth API (POST /auth/login).

Returns (VALUES AUTH-SESSION NIL) on success or (VALUES NIL LOGIN-FAILURE)
on rejection; transport errors propagate."
  (check-type username string)
  (check-type password string)
  (flet ((reject (code message)
           (values nil (make-login-failure :code code :message message))))
    (cond
      ((not (valid-username-p username))
       (reject "invalid_username"
               "Username must be 1-32 chars of [a-z0-9._-]."))
      ((zerop (length password))
       (reject "invalid_password" "Password must be non-empty."))
      (t
       (multiple-value-bind (status body)
           (funcall request-fn :post "/auth/login"
                    (jsown:to-json
                     (jsown:new-js
                       ("username" username)
                       ("password" password))))
         (case status
           (200
            (let* ((user (jsown:val body "user"))
                   (status-string (jsown:val user "status")))
              (values
               (make-auth-session
                :username (jsown:val user "username")
                :principal-type (jsown:val user "principal_type")
                :scopes (mapcar #'string (jsown:val user "scopes"))
                :status status-string
                :api-key (jsown:val body "api_key")
                :expires-in (ignore-errors
                              (jsown:val
                               (jsown:val body "credential") "expires_in")))
               nil)))
           (401 (reject "invalid_credential" "Authentication failed."))
           (otherwise
            (reject "auth_unavailable"
                    (format nil "Auth service returned status ~A." status)))))))))