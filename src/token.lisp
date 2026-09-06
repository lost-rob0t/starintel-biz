(in-package #:quasar-auth)

(defparameter *token-alphabet*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  "Quasar WebSocket session-token alphabet (URL-safe, no punctuation).")

(defparameter *token-octets* 32
  "Session-token entropy in random octets.")

(defun mint-session-token ()
  "Return a fresh unguessable quasar WebSocket session token."
  (let ((alphabet *token-alphabet*)
        (bytes (ironclad:random-data *token-octets*)))
    (with-output-to-string (stream)
      (map nil
           (lambda (byte)
             (write-char (char alphabet (mod byte (length alphabet))) stream))
           bytes))))
