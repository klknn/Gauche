;;;
;;; srfi-180 - JSON
;;;
;;;   Copyright (c) 2020 Shiro Kawai (shiro@acm.org)
;;;
;;;   Redistribution and use in source and binary forms, with or without
;;;   modification, are permitted provided that the following conditions
;;;   are met:
;;;
;;;   1. Redistributions of source code must retain the above copyright
;;;      notice, this list of conditions and the following disclaimer.
;;;
;;;   2. Redistributions in binary form must reproduce the above copyright
;;;      notice, this list of conditions and the following disclaimer in the
;;;      documentation and/or other materials provided with the distribution.
;;;
;;;   3. Neither the name of the authors nor the names of its contributors
;;;      may be used to endorse or promote products derived from this
;;;      software without specific prior written permission.
;;;
;;;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;;   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;;   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;;   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;;   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;;   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;;   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;

;; A wrapper of rfc.json

(define-module srfi-180
  (use gauche.parameter)
  (use parser.peg)                      ;<parse-error>
  (use rfc.json)
  (export json-error? json-error-reason json-null?

          json-nesting-depth-limit  ; in rfc.json
          json-number-of-character-limit

          json-generator ;json-fold
          ;;json-read json-lines-read json-sequence-read
          ;;json-accumulator json-write
          ))
(select-module srfi-180)

(define (json-error? obj)
  (or (is-a? obj <json-parse-error>)
      (is-a? obj <json-construct-error>)))

(define (json-error-reason obj)
  (~ obj'message))

(define (json-null? obj) (eq? obj 'null))

;; json-nesting-depth-limit is in rfc.json

(define json-number-of-character-limit (make-parameter +inf.0))


;; internal
;; we use peek-char to keep the last read char in the port, since
;; lseq read ahead one character and we don't want that character to
;; be missed in the subsequent read from the port.
(define (port->json-lseq port)
  (define nchars 0)
  (generator->lseq
   (^[]
     (unless (= nchars 0) (read-char port))
     (let1 c (peek-char port)
       (cond [(eof-object? c) c]
             [(>= nchars (json-number-of-character-limit))
              (error <json-parse-error>
                     "Input length exceeds json-number-of-character-limit")]
             [else (inc! nchars) c])))))

;; stream tokenizer.  
(define (json-generator :optional (port (current-input-port)))
  (define inner-gen
    (peg-parser->generator json-tokenizer (port->json-lseq port)))
  (define (nexttok)
    (guard (e ([<parse-error> e]
               ;; not to expose parser.peg's <parse-error>.
               (error <json-parse-error>
                      :position (~ e'position) :objects (~ e'objects)
                      :message (~ e'message))))
      (case (inner-gen)
        [(true) #t]
        [(false) #f]
        [else => identity])))
  (define nesting '())
  (define (push-nesting kind)
    (when (>= (length nesting) (json-nesting-depth-limit))
      (error <json-parse-error> "Input JSON nesting is too deep."))
    (push! nesting (cons kind gen)))
  (define (pop-nesting kind)
    (unless (pair? nesting)
      (errorf <json-parse-error> "Stray close ~a" kind))
    (unless (eq? (caar nesting) kind)
      (errorf <json-parse-error> "Unmatched open ~a" (car nesting)))
    (set! gen (cdr (pop! nesting))))
  (define (badtok tok)
    (error <json-parse-error> (format "Invalid token: ~s" tok)))

  ;; Read one value.  array-end and object-end are returned as-is, and the
  ;; caller should handle it---they can appear in value context input is empty
  ;; array and empty object.
  (define (value)
    (case (nexttok)
      [(array-start)
       (push-nesting 'array)
       (set! gen array-element)
       'array-start]
      [(object-start)
       (push-nesting 'object)
       (set! gen object-key)
       'object-start]
      [(#\: #\,) => badtok]
      [else => identity]))
  
  ;; State machine
  ;;  Each state is a thunk, set! to variable 'gen'.

  ;; Initial state
  (define (init)
    (set! gen fini)
    (case (value)
      [(array-end object-end) => badtok]
      [else => identity]))

  ;; We've already read a whole item.
  (define (fini) (eof-object))

  ;; Reading an array element.
  (define (array-element)
    (set! gen array-element-after)
    (case (value)
      [(array-end) (pop-nesting 'array) 'array-end]
      [(object-end) => badtok]
      [else => identity]))

  ;; Just read an array element.
  (define (array-element-after)
    (case (nexttok)
      [(#\,) (array-element)]
      [(array-end) (pop-nesting 'array) 'array-end]
      [else => badtok]))

  ;; Reading an object key
  (define (object-key)
    (let1 t (nexttok)
      (cond [(string? t) (set! gen object-key-after) t]
            [(eq? t 'object-end) (pop-nesting 'object) 'object-end]
            [else (badtok t)])))

  ;; Just read an object key
  (define (object-key-after)
    (case (nexttok)
      [(#\:)
       (set! gen object-value-after) 
       (case (value)
         [(array-end object-end) => badtok]
         [else => identity])]
      [else => badtok]))

  ;; Just read an object value
  (define (object-value-after)
    (case (nexttok)
      [(#\,) (object-key)]
      [(object-end) (pop-nesting 'object) 'object-end]
      [else => badtok]))

  ;; 'gen' will be set! to the next state handler.
  (define gen init)
  ;; Entry point
  (^[] (gen)))
                         
