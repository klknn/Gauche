;;;
;;;  Preliminary implementation of srfi-170
;;;

(define-module srfi-170
  (use gauche.fcntl)
  (use gauche.generator)
  (use gauche.parameter)
  (use data.random)
  (use srfi-13)
  (use srfi-19)
  (use file.util)
  (export open-file
          open/read open/write open/read+write open/append
          open/create open/exclusive open/nofollow open/truncate
          fdes->textual-input-port
          fdes->binary-input-port
          fdes->textual-output-port
          fdes->binary-output-port
          port-fdes
          close-fdes

          create-directory
          create-fifo
          create-hard-link
          create-symlink
          read-symlink
          rename-file
          delete-directory
          set-file-mode
          set-file-owner
          set-file-group
          set-file-timespecs
          truncate-file

          file-info
          file-info?
          file-info:device
          file-info:inode
          file-info:mode
          file-info:nlinks
          file-info:uid
          file-info:gid
          file-info:rdev
          file-info:size
          file-info:blksize
          file-info:blocks
          file-info:atime
          file-info:mtime
          file-info:ctime
          file-info-directory?
          file-info-fifo?
          file-info-symlink?
          file-info-regular?

          directory-files
          make-directory-files-generator
          open-directory
          read-directory
          close-directory

          real-path

          temp-file-prefix
          create-temp-file
          call-with-temporary-filename

          umask set-umask!
          current-directory set-current-directory!
          pid parent-pid process-group
          nice
          user-uid user-gid
          user-effective-uid user-effective-gid
          user-supplementary-gids

          user-info
          user-info?
          user-info:name
          user-info:uid
          user-info:gid
          user-info:home-dir
          user-info:shell
          user-info:full-name
          user-info:parsed-full-name

          group-info
          group-info?
          group-info:name
          group-info:gid

          posix-time
          monotonic-time

          set-environment-variable!
          delete-environment-variable!

          terminal?
          ))
(select-module srfi-170)

;; 3.2 I/O

(define-constant open/read       O_RDONLY)
(define-constant open/write      O_WRONLY)
(define-constant open/read+write O_RDWR)
(define-constant open/append     O_APPEND)
(define-constant open/create     O_CREAT)
(define-constant open/exclusive  O_EXCL)
(define-constant open/nofollow   (global-variable-ref 
                                  (find-module 'gauche.fcntl)
                                  'O_NOFOLLOW
                                  0))
(define-constant open/truncate   O_TRUNC)

(define (open-file fname flags :optional permission-bits)
  (sys-open fname flags permission-bits))

(define (%bufmode sym in?)
  (case sym
    [(none)  :none]
    [(block) :full]
    [(line)  (if in? :modest :line)]
    [else (error "Invalid buffering-mode: Must be one of (none block line), but got:" sym)]))

(define (fdes->textual-input-port fd :optional (bufmode 'block))
  (open-input-fd-port fd :buffering (%bufmode bufmode #t)))
(define (fdes->binary-input-port fd :optional (bufmode 'block))
  (open-input-fd-port fd :buffering (%bufmode bufmode #t)))
(define (fdes->textual-output-port fd :optional (bufmode 'block))
  (open-output-fd-port fd :buffering (%bufmode bufmode #f)))
(define (fdes->binary-output-port fd :optional (bufmode 'block))
  (open-output-fd-port fd :buffering (%bufmode bufmode #f)))

(define (port-fdes port) (port-file-number port))

(define (close-fdes fd) (sys-close fd))

;; 3.3 File system

(define (create-directory name :optional perm)
  (sys-mkdir name perm))
(define (create-fifo name :optional perm)
  (cond-expand
   [gauche.os.windows (error "create-fifo is not supported on this platform.")]
   [else (sys-mkfifo name perm)]))
(define (create-hard-link old new)
  (sys-link old new))
(define (create-symlink old new)
  (cond-expand
   [gauche.os.windows (error "create-symlink is not supported on this platform")]
   [else (sys-symlink old new)]))

(define (read-symlink name)
  (cond-expand
   [gauche.os.windows (error "read-symlink is not supported on this platform")]
   [else (sys-readlink name)]))

(define (rename-file old new) (sys-rename old new))

(define (delete-directory name) (sys-rmdir name))

(define (set-file-mode name mode) (sys-chmod name mode))
(define (set-file-owner name uid) (sys-chown name uid -1))
(define (set-file-group name gid) (sys-chown name -1 gid))

(define-constant timespec/now 'timespec/now)
(define-constant timespec/omit 'timespec/omit)

(define (set-file-timespecs fname :optional (atime 'timespec/now)
                                            (mtime 'timespec/now))
  (define-syntax argcheck
    (syntax-rules ()
      [(_ x)
       (cond [(eq? x 'timespec/now) #f]
             [(eq? x 'timespec/omit) #t]
             [else (assume-type x <time>)])]))
  (sys-utime fname (argcheck atime) (argcheck mtime)))

(define (truncate-file fname/port len)
  (assume (or (string? fname/port) (port? fname/port)))
  (cond [(string? fname/port)
         (sys-truncate fname/port len)]
        [(port? fname/port)
         (sys-ftruncate fname/port len)]))

(define (file-info fname/port follow?)
  (assume (or (string? fname/port) (port? fname/port)))
  (if (string? fname/port)
    (if follow?
      (sys-stat fname/port)
      (sys-lstat fname/port))
    (sys-fstat fname/port)))

(define (file-info? obj) (is-a? obj <sys-stat>))
(define (file-info:device stat)
  (assume-type stat <sys-stat>)
  (~ stat'dev))
(define (file-info:inode stat)
  (assume-type stat <sys-stat>)
  (~ stat'ino))
(define (file-info:mode stat)
  (assume-type stat <sys-stat>)
  (~ stat'mode))
(define (file-info:nlinks stat)
  (assume-type stat <sys-stat>)
  (~ stat'nlink))
(define (file-info:uid stat)
  (assume-type stat <sys-stat>)
  (~ stat'uid))
(define (file-info:gid stat)
  (assume-type stat <sys-stat>)
  (~ stat'gid))
(define (file-info:rdev stat)
  (assume-type stat <sys-stat>)
  (~ stat'rdev))
(define (file-info:size stat)
  (assume-type stat <sys-stat>)
  (~ stat'size))
(define (file-info:blksize stat)
  (assume-type stat <sys-stat>)
  4096)
(define (file-info:blocks stat)
  (assume-type stat <sys-stat>)
  (quotient (+ (~ stat'size) 511) 512))
(define (file-info:atime stat)
  (assume-type stat <sys-stat>)
  (~ stat'atim))
(define (file-info:mtime stat)
  (assume-type stat <sys-stat>)
  (~ stat'mtim))
(define (file-info:ctime stat)
  (assume-type stat <sys-stat>)
  (~ stat'ctim))

(define (file-info-directory? stat)
  (assume-type stat <sys-stat>)
  (eq? (~ stat'type) 'directory))
(define (file-info-fifo? stat)
  (assume-type stat <sys-stat>)
  (eq? (~ stat'type) 'fifo))
(define (file-info-symlink? stat)
  (assume-type stat <sys-stat>)
  (eq? (~ stat'type) 'symlink))
(define (file-info-regular? stat)
  (assume-type stat <sys-stat>)
  (eq? (~ stat'type) 'regular))

(define (directory-files dir :optional (dot? #f))
  (directory-list dir 
                  :children? #t
                  :filter (if dot? #f #/^[^\.]/)))

(define (make-directory-files-generator dir :optional (dot? #f))
  ;; can be more efficient
  (list->generator (directory-files dir dot?)))
                  
;; Gauche don't have a direct interface to opendir etc.
;; This is just an emulation.
(define-class <DIR> ()
  ((gen :init-keyword :gen)))

(define (open-directory dir :optional (dot? #f))
  (make <DIR> :gen (make-directory-files-generator dir dot?)))
(define (read-directory dirobj)
  (assume-type dirobj <DIR>)
  ((~ dirobj'gen)))
(define (close-directory dirobj)
  (assume-type dirobj <DIR>)
  (undefined))

(define (real-path path) (sys-realpath path))

(define temp-file-prefix 
  (make-parameter (build-path (temporary-directory)
                              (x->string (sys-getpid)))))

(define suffix-generator (strings-of 8 (chars$)))

(define-constant TEMP_RETRY_MAX 256)

(define (call-with-temporary-filename maker 
                                      :optional (prefix (temp-file-prefix)))
  (let loop ([i 0])
    (let1 f #"~|prefix|~(suffix-generator)"
      (receive (success . rest) (guard (e [else #f])
                                  (maker f))
        (if success
          (apply values success rest)
          (if (>= i TEMP_RETRY_MAX)
            (errorf "Couldn't create temporary file with prefix ~s" prefix)
            (loop (+ i 1))))))))

(define (create-temp-file :optional (prefix (temp-file-prefix)))
  (receive (port name) (sys-mkstemp prefix)
    (close-port port)
    name))

;;
;; 3.5 Process state
;;

(define (umask) (sys-umask))

(define (set-umask! umask) (sys-umask umask))

;; srfi-170#current-directory is a subset of file.util#current-directory

(define (set-current-directory! dir) (current-directory dir))

(define (pid) (sys-getpid))
(define (parent-pid) (sys-getppid))
(define (process-group) 
  (cond-expand
   [gauche.os.windows (error "process-group is not supported on this platform")]
   [else (sys-getpgrp)]))

(define (nice :optional (delta 1)) 
  (cond-expand 
   [gauche.os.windows (error "nice is not supported on this platform")]
   [else (sys-nice delta)]))

(define (user-uid) (sys-getuid))
(define (user-gid) (sys-getgid))
(define (user-effective-uid) (sys-geteuid))
(define (user-effective-gid) (sys-getegid))
(define (user-supplementary-gids)
  (cond-expand
   [gauche.os.windows (list (sys-getgid))]
   [else (sys-getgroups)]))

;;
;; 3.6 User and group database access
;;

(define (user-info uid/name)
  (assume (or (exact-integer? uid/name) (string? uid/name)))
  (if (string? uid/name)
    (sys-getpwnam uid/name)
    (sys-getpwuid uid/name)))

(define (user-info? obj) (is-a? obj <sys-passwd>))
(define (user-info:name uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'name))
(define (user-info:uid uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'uid))
(define (user-info:gid uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'gid))
(define (user-info:home-dir uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'dir))
(define (user-info:shell uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'shell))
(define (user-info:full-name uinfo)
  (assume-type uinfo <sys-passwd>)
  (~ uinfo'gecos))
(define (user-info:parsed-full-name uinfo)
  (assume-type uinfo <sys-passwd>)
  ;; This cond-expand is based on the srfi-170 spec
  (cond-expand
   [gauche.os.windows (list (~ uinfo'gecos))]
   [else (let1 fields (string-split (~ uinfo'gecos) ",")
           (if (null? fields)
             fields
             (cons (regexp-replace-all #/&/ (car fields)
                                       (^_ (string-titlecase (~ uinfo'name))))
                   (cdr fields))))]))

(define (group-info gid/name)
  (assume (or (exact-integer? gid/name) (string? gid/name)))
  (if (string? gid/name)
    (sys-getgrnam gid/name)
    (sys-getgrgid gid/name)))
(define (group-info? obj) (is-a? obj <sys-group>))
(define (group-info:name ginfo)
  (assume-type ginfo <sys-group>)
  (~ ginfo'name))
(define (group-info:gid ginfo)
  (assume-type ginfo <sys-group>)
  (~ ginfo'gid))

;;
;; 3.10 Time
;;

(define (posix-time) (current-time))

(define monotonic-time
  (let1 last-time (current-time)
    (^[] (let1 now (current-time)
           (when (time<=? last-time now) (set! last-time now))
           last-time))))

;;
;; 3.11 Environment variables
;;

(define (set-environment-variable! name value)
  (sys-setenv name value #t))
(define (delete-environment-variable! name)
  (sys-unsetenv name))

;;
;; 3.12 Terminal device control
;;

(define (terminal? port) (sys-isatty port))
