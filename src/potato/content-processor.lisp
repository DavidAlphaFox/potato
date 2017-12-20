(in-package :potato.content-processor)

(declaim #.potato.common::*compile-decl*)

(defvar *url-content-processors* nil)

(defun register-url-processor (handler url-regexps)
;; register url processor with handler 
  (check-type handler symbol)
  ;; make suere the handler is a symbol
  (let ((removed (remove handler *url-content-processors* :key #'cdr)))
    ;; remove the handler from *url-content-processors* 
    ;; the map of *url-content-processors*  is (url,handler)
    ;; remove is a function of Common Lisp 
    ;; removed contains all items without handler
    (setf *url-content-processors*
          (append (mapcar (lambda (v)
                            (cons (cl-ppcre:create-scanner v) handler))
                          url-regexps)
                  removed))))

(defun find-urls-in-content (text)
  (let ((parsed (markup-message-content text)))
    ;; parsed markup
    (labels ((search-fields (fields)
               (loop
                  for entry in fields
                  for result = (if (listp entry)
                                   (case (car entry)
                                     (:url (list (second entry)))
                                     (:paragraph (search-fields (cdr entry))))
                                   nil)
                  if result
                  append result)))
      (search-fields parsed))))

(defun process-update (msg)
  ;; process msg
  (let* ((content (st-json:read-json-from-string (babel:octets-to-string (cl-rabbit:message/body (cl-rabbit:envelope/message msg)) :encoding :utf-8)))
         (text (st-json:getjso "text" content))
         (urls (find-urls-in-content text)))
    ;; get urls in content
    (loop
       for url in urls
       do (loop
             for handler in *url-content-processors*
             ;; loop to find the handler of url
             do (multiple-value-bind (match strings)
                    (cl-ppcre::scan-to-strings (car handler) url)
                  (when match
                    (funcall (cdr handler) strings content
                    ;; call processor with callback
                             (lambda (text)
                               (with-pooled-rabbitmq-connection (conn)
                                 (let ((message-id (st-json:getjso "id" content))
                                       (channel-id (st-json:getjso "channel" content)))
                                   (cl-rabbit:basic-publish conn 1
                                                            :exchange *chat-image-converter-response-exchange-name*
                                                            :routing-key channel-id
                                                            :body (lisp-to-binary `(:update (,message-id :extra-html ,text))))))))
                    (return-from process-update nil)))))))

(defun content-processor-loop ()
  (with-rabbitmq-connected (conn)
    (cl-rabbit:basic-consume conn 1 *content-processor-queue-name* :no-ack t)
    (loop
       for msg = (cl-rabbit:consume-message conn)
       do (process-update msg))))

(defun start-message-content-processor-thread ()
  (start-monitored-thread #'content-processor-loop "Content processor loop"))
