#!/usr/bin/env sbcl --noinform

(require :asdf)

;;reading comman line arguments
;(dolist (element uiop:*command-line-arguments*)
;  (uiop:writeln element)
;  (write-line element));; look the different output

(defvar *freebsd-type* "FreeBSD")

(defun freebsd-update ()
  (format t "Checking for FreeBSD patches~%")
  (uiop:run-program (list "/usr/sbin/freebsd-update" "Fetch") :ignore-error-status t)
  (uiop:run-program (list "/usr/sbin/freebsd-update" "install") :ignore-error-status t))

(defun portsnap (an-action)
  (format t "Portsnap ~s~%" an-action)
  (uiop:run-program (list "/usr/sbin/portsnap" "--interactive" an-action) :output nil))

(defun cmd-package-install (a-package)
  (cond ((string= (software-type) *freebsd-type*)
         (format t "FreeBSD pkg installing ~s~%" a-package)
         (uiop:run-program `("/usr/sbin/pkg" "install" "-yqU" ,a-package) :output *standard-output* :error *standard-output*))
        (t (error "Platform ~s (~s) on ~s is not supported~%" (software-type) (software-version) (machine-type)))))

(defun cmd-package (a-command a-package)
  (cond ((string= a-command "install") (cmd-package-install a-package))))

(defun pkg-info (a-package)
  (uiop:run-program (list "/usr/sbin/pkg" "info" a-package)))

(defun has-user? (a-user)
  (handler-case
      (progn (uiop:run-program (list "/usr/sbin/pw" "user" "show" a-user))
             t)
    (uiop:subprocess-error() nil)))

(defun has-group? (a-group)
  (handler-case
      (progn (uiop:run-program (list "/usr/sbin/pw" "group" "show" a-group))
             t)
    (uiop:subprocess-error() nil)))

;-- MAIN

(format t "Hello World!~%")

(when (string= (uiop:hostname) "")
  (uiop:run-program (list "/bin/hostname" "potato"))
  (with-open-file (stream "/etc/rc.conf" :direction :io :if-exists :overwrite)
    (let ((found-hostname (loop for line = (read-line stream nil)
                             while line
                               thereis (search "hostname=" line))))
      (unless found-hostname
        (format t "add hostname to rc.conf~%")
        (format stream "hostname=\"potato\"~%")))))

(when (string= (software-type) *freebsd-type*)
  (freebsd-update))

; erlang is a super dependency of couchdb and rabbitmq
; openjdk8 pulls libXt and depends on a whole list of X-related packages
(dolist (p '("rsync" "sudo" "curl" "git" "bzip2" "zip" "unzip" "bash" "lsof" "gnutls" "openssl"
             "ImageMagick-nox11" "npm" "haproxy"
             "autoconf" "libtool" "automake" ;; for libfixposix
             "erlang" "couchdb" "rabbitmq" "openjdk8" "memcached" "rabbitmq-c-devel" "leiningen"))
  (cmd-package "install" p))

(with-open-file (stream "/usr/local/etc/sudoers" :direction :io :if-exists :overwrite)
  (let ((found-root (loop for line = (read-line stream nil)
                       while line
                       thereis (search "root " line))))
    (unless found-root
      (format t "add root to sudoers file~%")
      (format stream "root ALL=(ALL) NOPASSWD: ALL"))))

(with-open-file (stream "/etc/fstab" :direction :io :if-exists :OVERWRITE)
  (let ((found-fs (loop for line = (read-line stream nil)
                     while line
                     when (search "fdescfs" line)
                     collect :fdescfs
                     when (search "procfs" line)
                     collect :procfs)))
    ;; position is now at the end of the file, we can safely append
    (unless (member :fdescfs found-fs)
      (format stream "fdesc   /dev/fd     fdescfs     rw  0   0~%")
      (format t "added fdescfs to /etc/fstab~%"))
    (unless (member :procfs found-fs)
      (format stream "proc    /proc       procfs      rw  0   0~%")
      (format t "added procfs to /etc/fstab~%"))))

;; mount all new filesystems
(uiop:run-program (list "/sbin/mount" "-a"))

(portsnap "fetch")
(handler-case
    (portsnap "update")
  ;; update failed, maybe we should try "extract" for the initial portsnap
  (uiop:subprocess-error () (portsnap "extract")))

(handler-case
    (pkg-info "nginx-devel")
  ;; "info" failed, which probably means we do not have nginx-devel installed yet
  (uiop:subprocess-error ()
    (format t "Installing nginx~%")
    (uiop:chdir "/usr/ports/www/nginx-devel")
    (uiop:run-program (list "/usr/bin/make" "-DWITH=\"HTTPV2\"" "install" "clean" "BATCH=yes"))))

(format t "Recompile SBCL with threads support~%")
(uiop:chdir "/potato/deploy/files/sbcl")
(uiop:run-program (list "/usr/bin/make" "-DWITH=\"FANCY\"" "reinstall" "clean" "BATCH=yes") :output *standard-output* :error *standard-output*)

(let* ((solr-version  "5.4.0")
       (solr-checksum "f906356e01eebb08e856a7c64250ba53")
       (solr-ext      ".tgz")
       (solr-mirror   "http://www.us.apache.org/dist/lucene/solr/")
       (solr-fullname (format nil "solr-~a" solr-version))
       (solr-filename (format nil "~a~a" solr-fullname solr-ext))
       (solr-basedir  "/usr/local")
       (solr-installdir (format nil "~a/~a" solr-basedir solr-fullname))
       (solr-url      (format nil "~a/~a/~a" solr-mirror solr-version solr-filename))
       (tmp-dir       "/tmp"))
  (uiop:chdir tmp-dir)
  (unless (uiop:directory-exists-p solr-installdir)
    (if (uiop:file-exists-p (format nil "~a/~a" tmp-dir solr-filename))
        (uiop:run-program (list "/sbin/md5" "-c" solr-checksum solr-filename))
        (progn
          (format t "Downloading SolR~%")
          (uiop:run-program (list "/usr/local/bin/curl" "-O" solr-url) :output *standard-output* :error *standard-output*)
          (uiop:run-program (list "/sbin/md5" "-c" solr-checksum solr-filename))))

    (format t "Extracting SolR~%")
    (uiop:run-program (list "/usr/bin/tar" "-zx" "-C" solr-basedir "-f" (format nil "~a/~a" tmp-dir solr-filename))))
  (uiop:run-program (list "/bin/cp" "-r" "/potato/deploy/files/solr/potato" (format nil "~a/server/solr" solr-installdir)))
  (unless (has-user? "solr")
    (format t "Creating SolR user~%")
    (uiop:run-program (list "/usr/sbin/pw" "useradd" "-n" "solr" "-u" "808" "-d" solr-installdir "-c" "SolR account"))))

(unless (uiop:file-exists-p "/usr/local/lib/libfixposix.so")
  (format t "Installing libfixposix~%")
  (uiop:chdir "/tmp")
  (uiop:run-program (list "/usr/local/bin/curl" "-o" "libfixposix.zip" "https://codeload.github.com/sionescu/libfixposix/zip/master"))
  (uiop:run-program (list "/usr/bin/unzip" "/tmp/libfixposix.zip"))
  (uiop:chdir "/tmp/libfixposix-master")
  (uiop:run-program (list "/usr/local/bin/autoreconf" "-i" "-f"))
  (uiop:run-program (list "./configure"))
  (uiop:run-program (list "make"))
  (uiop:run-program (list "make" "install")))

(unless (has-group? "users")
  (format t "Creating users group~%")
  (uiop:run-program (list "/usr/sbin/pw" "groupadd" "-n" "users" "-g" "100")))

(unless (has-user? "potato")
  (format t "Creating Potato user~%")
  (uiop:run-program (list "/usr/sbin/pw" "useradd" "-n" "potato" "-u" "1214" "-g" "users" "-c" "Potato user" "-m")))

(uiop:chdir "/home/potato")

(unless (uiop:directory-exists-p "/home/potato/quicklisp")
  (format t "Installing Quicklisp~%")
  (uiop:run-program (list "/usr/local/bin/curl" "-O" "https://beta.quicklisp.org/quicklisp.lisp"))
  (uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/sbcl" "--noinform" "--non-interactive" "--noprint" "--load" "/home/potato/quicklisp.lisp" "--eval" "(quicklisp-quickstart:install)") :output *standard-output* :error *standard-output*)

  (with-open-file (stream "/home/potato/.sbclrc" :direction :output :if-exists :rename)
    (format stream "#-quicklisp~%")
    (format stream "(let ((quicklisp-init (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname))))~%")
    (format stream "     (when (probe-file quicklisp-init) (load quicklisp-init)))~%")))

;; rsync -rtv source_folder/ destination_folder/
(unless (uiop:directory-exists-p "/home/potato/potato")
  (format t "Cloning public repository~%")
  (uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/git" "clone" "https://github.com/cicakhq/potato.git"))
  (uiop:chdir "/home/potato/potato")
  (format t "Initialising submodules~%")
  (uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/git" "submodule" "init"))
  (uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/git" "submodule" "update")))

(unless (uiop:file-exists-p "/home/potato/potato/potato.bin")
  (format t "Building the lisp binary~%")
  (uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "./tools/build_binary.sh")))

(uiop:chdir "/home/potato/potato/web-app")
(format t "Pulling CLJS dependencies~%")
(uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/lein" "with-profile" "-dev" "deps") :output *standard-output* :error *standard-output*)
(format t "Building the CLJS web application~%")
(uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/lein" "with-profile" "-dev" "cljsbuild" "once" "prod" "admin-prod") :output *standard-output* :error *standard-output*)

(format t "Pulling GULP dependencies and building the CSS~%")
(uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "/usr/local/bin/npm" "install") :output *standard-output* :error *standard-output*)

(with-open-file (stream "/etc/rc.conf" :direction :io :if-exists :OVERWRITE)
  (let ((found-rc (loop for line = (read-line stream nil)
                     while line
                     when (search "couchdb_enable" line)
                     collect :couchdb
                     when (search "memcached_enable" line)
                     collect :memcached
                     when (search "rabbitmq_enable" line)
                     collect :rabbitmq)))
    ;; position is now at the end of the file, we can safely append
    (unless (member :couchdb found-rc)
      (format stream "couchdb_enable=\"YES\"~%")
      (format t "Added couchdb to /etc/rc.conf~%"))
    (unless (member :memcached found-rc)
      (format stream "memcached_enable=\"YES\"~%")
      (format t "Added memcached to /etc/rc.conf~%"))
    (unless (member :rabbitmq found-rc)
      (format stream "rabbitmq_enable=\"YES\"~%")
      (format t "Added rabbitmq to /etc/rc.conf~%"))))

(format t "Start CouchDB, Memcached and RabbitMQ~%")
(dolist (the-service '("couchdb" "memcached" "rabbitmq"))
  (uiop:run-program (list (format nil "/usr/local/etc/rc.d/~a" the-service) "start") :output *standard-output* :error *standard-output*))

(uiop:chdir "/home/potato/potato/")
(format t "Init of the CouchDB database")
(uiop:run-program (list "/usr/local/bin/sudo" "-u" "potato" "./potato.bin" "-c" "potato.cfg" "--init"))

