#lang at-exp racket/base
(require ffi/unsafe
         racket/list
         racket/stxparam
         racket/splicing
         racket/bool
         (for-syntax racket/base
                     racket/syntax
                     racket/stxparam-exptime)
         (except-in racket/contract ->)
         (prefix-in c: racket/contract)
         scribble/srcdoc)
(require/doc racket/base
             (for-label (except-in racket/contract ->))
             scribble/manual)

(define zmq-lib (ffi-lib "libzmq"))

(define-syntax-rule (define-zmq* (external internal) type)
  (define external
    (get-ffi-obj 'internal zmq-lib type)))

(define-syntax-parameter current-zmq-fun #f)
(define-syntax-rule (define-zmq (external internal)
                      (-> [name name/c] ...
                          result/c)
                      type)
  (begin
    (splicing-syntax-parameterize
     ([current-zmq-fun 'external])
     (define-zmq* (external internal) type))
    (provide/doc
     [proc-doc/names
      external (c:-> name/c ... result/c)
      (name ...) @{An FFI binding for
                   @link[(format "http://api.zeromq.org/~a.html" 'internal)]{@symbol->string['internal]}.}])))

;;

(define-cpointer-type _context)
(define-cpointer-type _socket)
(provide/doc
 [proc-doc/names
  context? (c:-> any/c boolean?)
  (x) @{Determines if @racket[x] is a pointer to a ZeroMQ context.}]
 [proc-doc/names
  socket? (c:-> any/c boolean?)
  (x) @{Determines if @racket[x] is a pointer to a ZeroMQ socket.}])

(define socket/c (flat-named-contract 'socket socket?))

(define-syntax-rule (define-zmq-symbols _type type?
                      [sym = num] ...)
  (begin
    (define _type
      (_enum (append '[sym = num] ...) _int))
    (define type?
      (c:symbols 'sym ...))
    (provide/doc
     [thing-doc
      type? contract?
      @{A contract for the symbols @racket['(sym ...)]}])))
(define-syntax-rule (define-zmq-bitmask _base _type type?
                      [sym = num] ...)
  (begin
    (define _type
      (_bitmask (append '[sym = num] ...) _base))
    (define type-symbol?
      (c:symbols 'sym ...))
    (define type?
      (c:or/c type-symbol? (c:listof type-symbol?)))
    (provide/doc
     [thing-doc
      type? contract?
      @{A contract for any symbol in @racket['(sym ...)] or any list of those symbols.}])))

(define-zmq-symbols _socket-type socket-type?
  [PAIR = 0]
  [PUB = 1]
  [SUB = 2]
  [REQ = 3]
  [REP = 4]
  [DEALER = 5]
  [ROUTER = 6]
  ; XREQ/XREQ deprecated in favour of DEALER/ROUTER and currently alias
  [XREQ = 5]
  [XREP = 6]
  [PULL = 7]
  [PUSH = 8]
  [XPUB = 9]
  [XSUB = 10])
(define-zmq-symbols _option-name option-name?
  [AFFINITY = 4]
  [IDENTITY = 5]
  [SUBSCRIBE = 6]
  [UNSUBSCRIBE = 7]
  [RATE = 8]
  [RECOVERY_IVL = 9]
  [MCAST_LOOP = 10]
  [SNDBUF = 11]
  [RCVBUF = 12]
  [RCVMORE = 13]
  [FD = 14]
  [EVENTS = 15]
  [SNDHWM = 23]
  [RCVHWM = 24]
  [LAST_ENDPOINT = 32])
(define-zmq-bitmask _int _send/recv-flags send/recv-flags?
  [DONTWAIT = 1]
  [NOBLOCK = 1] ; NOBLOCK has been replaced with DONTWAIT, leaving in for compatibility
  [SNDMORE = 2])
(define-zmq-bitmask _int _poll-status poll-status?
  [POLLIN = 1]
  [POLLOUT = 2]
  [POLLERR = 4])

(define _size_t _int)
(define _uchar _uint8)

(require (for-syntax racket/base syntax/parse unstable/syntax))
(define-syntax (define-cvector-type stx)
  (syntax-parse
   stx
   [(_ name:id _type:expr size:number)
    (with-syntax
        ([(field ...)
          (for/list ([i (in-range (syntax->datum #'size))])
            (format-id #f "f~a" i))])
      (syntax/loc stx
        (define-cstruct name
          ([field _type]
           ...))))]))

(define-cvector-type _ucharMAX _uchar 30)
(define-cstruct _msg
  ([content _pointer]
   [flags _uchar]
   [vsm_size _uchar]
   [vsm_data _ucharMAX]))
(provide/doc
 [proc-doc/names
  msg? (c:-> any/c boolean?)
  (x) @{Determines if @racket[x] is a ZeroMQ message.}]
 [thing-doc
  _msg ctype?
  @{A ctype for ZeroMQ messages, suitable for using with @racket[malloc].}])

(define-cstruct _poll-item
  ([socket _socket]
   [fd _int]
   [events _poll-status]
   [revents _poll-status]))
(provide/doc
 [proc-doc/names
  poll-item? (c:-> any/c boolean?)
  (x) @{Determines if @racket[x] is a ZeroMQ poll item.}]
 [proc-doc/names
  make-poll-item (c:-> socket? exact-nonnegative-integer? poll-status? poll-status?
                       poll-item?)
  (socket fd events revents)
  @{Constructs a poll item for using with @racket[poll!].}]
 [proc-doc/names
  poll-item-revents (c:-> poll-item? poll-status?)
  (pi) @{Extracts the @litchar{revents} field from a poll item structure.}])

;; Errors
(define-zmq*
  [errno zmq_errno]
  (_fun -> _int))
(define-zmq*
  [strerro zmq_strerror]
  (_fun _int -> _string))

(define-syntax (zmq-error stx)
  (syntax-case stx ()
    [(_)
     (quasisyntax/loc stx
       (error '#,(syntax-parameter-value #'current-zmq-fun)
              "~a: ~a"
              (errno)
              (strerro (errno))))]))

;; Context
(define-zmq
  [context zmq_init]
  (-> [io_threads exact-nonnegative-integer?]
      context?)
  (_fun [io_threads : _int]
        -> [context : _context/null]
        -> (or context (zmq-error))))

(define-zmq
  [context-close! zmq_term]
  (-> [context context?] void)
  (_fun [context : _context]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(module+ test
  (require rackunit)
  (test-case
   "call-with-context"
   (call-with-context (λ (context)
                        ;; check if it returns a context
                        (check-true (context? context)))))
  (test-exn
    "raises exception when procedure is missing an argument"
    exn:fail:contract?
    (λ ()
      (call-with-context (λ () (void)))))
  (test-exn
    "raises exception when the number thread count is not exact non-negative integer"
    exn:fail?
    (λ ()
      (call-with-context #:io-threads -1 (λ (context) (void))))))

(define (call-with-context procedure #:io-threads [io-threads 1])
  (let ([ctx (context io-threads)])
    (dynamic-wind
      void
      (lambda ()
        (procedure ctx) (void))
      (lambda ()
        (context-close! ctx)))))
(provide/doc
 [proc-doc/names
  call-with-context (->* ((procedure-arity-includes/c 1)) (#:io-threads exact-nonnegative-integer?) void)
 ((procedure) ((io-threads 1)))
  @{Using the @racket[context] procedure, @racket[call-with-context] creates a context and passes it to a procedure with one argument. On return, it closes the context using @racket[context-close!]}])

;; Message
(define-zmq
  [msg-init! zmq_msg_init]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-init-size! zmq_msg_init_size]
  (-> [msg msg?] [size exact-nonnegative-integer?] void)
  (_fun _msg-pointer _size_t
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-close! zmq_msg_close]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-data-pointer zmq_msg_data]
  (-> [msg msg?] cpointer?)
  (_fun _msg-pointer -> _pointer))
(define-zmq
  [msg-size zmq_msg_size]
  (-> [msg msg?] exact-nonnegative-integer?)
  (_fun _msg-pointer -> _size_t))

(define (msg-data m)
  (make-sized-byte-string (msg-data-pointer m) (msg-size m)))
(provide/doc
 [proc-doc/names
  msg-data (c:-> msg? bytes?)
  (msg) @{Creates a sized byte string from a message's data.}])

;; Returns a pointer tag with msg suitable for adding data, and
;; for sending and receiving
(define (malloc-msg)
  (let ([_msg-ctype (malloc _msg 'raw)])
    (set-cpointer-tag! _msg-ctype msg-tag)
    _msg-ctype))

(module+ test
  (test-case
   "make-empty-msg"
   (define msg (make-empty-msg))
   (check-true (msg? msg))
   (check-equal? (bytes-length (msg-data msg)) 0)
   (free msg)))

(define (make-empty-msg)
  (let ([msg (malloc-msg)])
    (msg-init! msg)
    msg))
(provide/doc
 [proc-doc/names
  make-empty-msg (c:-> msg?)
  ()
  @{Returns a _msg ctype with no data. The _msg must be manually deallocated using @racket[free]}])

(module+ test
  (test-case
   "make-msg-with-data"
   (define data #"Hello")
   (define length (bytes-length data))
   (define msg (make-msg-with-data data))
   (check-true (msg? msg))
   (check-equal? (msg-data msg) data)
   (free msg)
   (check-exn
    exn:fail:contract?
    (λ ()
      (make-msg-with-data "not-a-byte-string")))))
(define (make-msg-with-data bs)
  (let* ([length (bytes-length bs)]
         [msg (make-msg-with-size length)])
    (memcpy (msg-data-pointer msg) bs length)
    msg))
(provide/doc
 [proc-doc/names
  make-msg-with-data (c:-> bytes? msg?)
  (bytes)
  @{Returns a _msg ctype whose msg-data is set to given the byte string. The _msg must be manually deallocated using @racket[free]}])

(module+ test
  (test-case
   "make-msg-with-size"
   (define size 8)
   (define msg (make-msg-with-size size))
   (check-true (msg? msg))
   (check-eq? (msg-size msg) size)
   (free msg)
   (check-exn
    exn:fail:contract?
    (λ ()
      (make-msg-with-size "not-an-integer")))))
(define (make-msg-with-size size)
  (let ([msg (malloc-msg)])
    (msg-init-size! msg size)
    msg))
(provide/doc
 [proc-doc/names
  make-msg-with-size (c:-> exact-nonnegative-integer? msg?)
  (exact-nonnegative-integer)
  @{Returns a _msg ctype whose size is set the given non-negative integer. The _msg must be manually deallocated using @racket[free]}])

(define-zmq
  [msg-copy! zmq_msg_copy]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-move! zmq_msg_move]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

;; Socket
(define-zmq
  [socket zmq_socket]
  (-> [ctxt context?] [type socket-type?] socket?)
  (_fun _context _socket-type
        -> [sock : _socket] -> (or sock (zmq-error))))
(define-zmq
  [socket-close! zmq_close]
  (-> [socket socket?] void)
  (_fun _socket
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(module+ test
  (test-case
   "call-with-socket"
   (test-exn
    "raises a contract error when a context is not used to create the socket"
    exn:fail:contract?
    (λ ()
     (call-with-socket "not-a-context" 'REP (λ (socket) (void))))))
  (call-with-context
   (λ (context)
     (test-exn
      "raises exception when it receives an invalid socket type"
      exn:fail:contract?
      (λ ()
       (call-with-socket context 'BLAH (λ (socket) (void)))))))
  (call-with-context
   (λ (context)
     (test-exn
      "raises exception when it does not receive a procedure with one arguement"
      exn:fail:contract?
      (lambda ()
       (call-with-socket context 'BLAH (λ () (void))))))))

(define (call-with-socket context socket-type procedure)
  (let ([skt (socket context socket-type)])
    (dynamic-wind
      void
      (lambda ()
        (procedure skt) (void))
      (lambda ()
        (socket-close! skt)))))
(provide/doc
 [proc-doc/names
  call-with-socket (c:-> context? socket-type? (procedure-arity-includes/c 1) void)
 (context socket-type procedure)
  @{Using the @racket[socket] procedure, @racket[call-with-socket] creates a socket of a valid @racket[socket-type?] using a previously created context. It passes the socket to a procedure with one argument. On return, it closes the socket using @racket[socket-close!]}])

(define-syntax (define-zmq-socket-options stx)
  (syntax-case stx ()
    [(_ [external internal]
        ([_type after type? opt ...] ...)
        ([byte-opt byte-opt-size] ...))
     (with-syntax ([(_type-external ...) (generate-temporaries #'(_type ...))])
       (syntax/loc stx
         (begin
           (splicing-syntax-parameterize
            ([current-zmq-fun 'external])
            (define-zmq* [_type-external internal]
              (_fun _socket _option-name
                    [option-value : (_ptr o _type)]
                    [option-size : (_ptr io _size_t) = (ctype-sizeof _type)]
                    -> [err : _int]
                    -> (if (zero? err)
                           option-value
                           (zmq-error))))
            ...
            (define-zmq* [byte-external internal]
              (_fun _socket
                    [oname : _option-name]
                    [option-value : (_bytes o (case oname [(byte-opt) byte-opt-size] ...))]
                    [option-size : (_ptr io _size_t) = (case oname [(byte-opt) byte-opt-size] ...)]
                    -> [err : _int]
                    -> (if (zero? err)
                           (subbytes option-value 0 option-size)
                           (zmq-error)))))
           (define (external sock opt-name)
             (case opt-name
               [(opt ...) (after (_type-external sock opt-name))]
               ...
               [(byte-opt ...) (byte-external sock opt-name)]))
           (provide/doc
            [proc-doc/names
             external (c:-> socket? option-name? (or/c type? ... bytes?))
             (socket option-name)
             @{Extracts the given option's value from the socket, similar to
               @link[(format "http://api.zeromq.org/~a.html" 'zmq_getsockopt)]{@symbol->string['zmq_getsockopt]}.}]))))]))

(define-zmq-socket-options
  [socket-option zmq_getsockopt]
  ([_int64 zero? boolean?
           RCVMORE MCAST_LOOP]
   [_int64 (λ (x) x) exact-integer?
           RATE RECOVERY_IVL]
   [_int (λ (x) x) exact-integer?
         FD]
   [_poll-status (λ (x) x) poll-status?
                 EVENTS]
   [_uint64 (λ (x) x) exact-nonnegative-integer?
            SNDHWM RCVHWM AFFINITY SNDBUF RCVBUF])
  ([IDENTITY 255] [LAST_ENDPOINT 1024]))

(define-syntax (define-zmq-set-socket-options! stx)
  (syntax-case stx ()
    [(_ [external internal]
        ([type? before _type opt ...] ...)
        (byte-opt ...))
     (with-syntax ([(_type-external ...) (generate-temporaries #'(_type ...))])
       (syntax/loc stx
         (begin
           (splicing-syntax-parameterize
            ([current-zmq-fun 'external])
            (define-zmq* [_type-external internal]
              (_fun _socket _option-name
                    [option-value : _type]
                    [option-size : _size_t = (ctype-sizeof _type)]
                    -> [err : _int] -> (unless (zero? err) (zmq-error))))
            ...
            (define-zmq* [byte-external internal]
              (_fun _socket _option-name
                    [option-value : _bytes]
                    [option-size : _size_t = (bytes-length option-value)]
                    -> [err : _int] -> (unless (zero? err) (zmq-error)))))
           (define (external sock opt-name opt-val)
             (case opt-name
               [(opt ...) (_type-external sock opt-name (before opt-val))]
               ...
               [(byte-opt ...) (byte-external sock opt-name opt-val)]))
           (provide/doc
            [proc-doc/names
             external (c:-> socket? option-name? (or/c type? ... bytes?) void)
             (socket option-name option-value)
             @{Sets the given option's value from the socket, similar to
               @link[(format "http://api.zeromq.org/~a.html" 'zmq_setsockopt)]{@symbol->string['zmq_setsockopt]}.}]))))]))

(define-zmq-set-socket-options!
  [set-socket-option! zmq_setsockopt]
  ([exact-nonnegative-integer? (λ (x) x) _uint64
                               SNDHWM RCVHWM AFFINTY SNDBUF RCVBUF]
   [exact-integer? (λ (x) x) _int64
                   RATE RECOVER_IVL]
   [boolean? (λ (x) (if x 1 0)) _int64
             MCAST_LOOP])
  (IDENTITY SUBSCRIBE UNSUBSCRIBE LAST_ENDPOINT))

(define-zmq
  [socket-bind! zmq_bind]
  (-> [socket socket?] [endpoint string?] void)
  (_fun _socket _string
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [socket-connect! zmq_connect]
  (-> [socket socket?] [endpoint string?] void)
  (_fun _socket _string
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [socket-send-msg! zmq_msg_send]
  (-> [msg msg?] [socket socket?] [flags send/recv-flags?] exact-integer?)
  (_fun _msg-pointer _socket _send/recv-flags
        -> [bytes-sent : _int] -> (if (negative? bytes-sent) (zmq-error) bytes-sent)))

;;;; helpers for blocking send and receive that don't block other threads
(define scheme-fd-to-semaphore
  (get-ffi-obj "scheme_fd_to_semaphore" #f
               (_fun _int _int _int -> _scheme)))

(define (thread-wait-read fd)
  ;; MZFD_CREATE_READ = 1
  ;; is_socket = 1
  (semaphore-wait/enable-break (scheme-fd-to-semaphore fd 1 1)))

(define (wait socket poll-event)
  (define e (socket-option socket 'EVENTS))
  (unless (member poll-event e)
    (define fd (socket-option socket 'FD))
    (thread-wait-read fd)
    (wait socket poll-event)))

(define/contract (retry on-block act)
  (procedure? (c:-> integer?) . c:-> . any/c)
  (define (handle-err e)
    (cond [(= e (lookup-errno 'EINTR))
           (retry on-block act)]
          [(= e (lookup-errno 'EAGAIN))
           ;; assumes 'EWOULDBLOCK is the same as 'EAGAIN,
           ;; because lookup-errno doesn't support 'EWOULDBLOCK
           (on-block)
           (retry on-block act)]
          [else (zmq-error)]))
  (define result (act))
  (if (= -1 result)
      (handle-err (errno))
      result))
;;;; end helpers

(define (call-with-message act #:data [data #f])
  (define m (malloc-msg))
  (dynamic-wind
   void
   (λ ()
     (cond [data
            (define len (bytes-length data))
            (msg-init-size! m len)
            (memcpy (msg-data-pointer m) data len)]
           [else (msg-init! m)])
     (dynamic-wind
       void
       (λ () (act m))
       (λ () (msg-close! m))))
   (λ () (free m))))

(define-zmq*
  [socket-send-msg-internal! zmq_msg_send]
  (_fun _msg-pointer _socket _send/recv-flags -> _int))

(module+ test
  (require (submod ".."))
  (define expected-request (string->bytes/utf-8 "hello"))
  (define expected-request2 (string->bytes/utf-8 "world"))
  (define expected-response (string->bytes/utf-8 "goodybe moon"))
  (define endpoint "tcp://127.0.0.1:*")
  (test-case "socket-send! and socket-recv!"
    (define server
      (thread
       (λ ()
         (define full-endpoint (thread-receive))
         (call-with-context
          (λ (ctx)
            (call-with-socket ctx 'REP
              (λ (s)
                (socket-connect! s full-endpoint)
                (define request (socket-recv! s))
                (check-equal? expected-request request)
                (define request2 (socket-recv! s))
                (check-equal? expected-request2 request2)
                (socket-send! s expected-response))))))))
    (define client
      (thread
       (λ ()
         (call-with-context
          (λ (ctx)
            (call-with-socket ctx 'REQ
              (λ (s)
                (socket-bind! s endpoint)
                (define full-endpoint (bytes->string/utf-8 (socket-option s 'LAST_ENDPOINT)))
                (thread-send server full-endpoint)
                (socket-send! s expected-request #:flags 'SNDMORE)
                (socket-send! s expected-request2)
                (define response (socket-recv! s))
                (check-equal? expected-response response))))))))
    (thread-wait server)
    (thread-wait client)))

(define (socket-send! s bs #:flags [flags '()])
  (define flag-list (if (list? flags) flags (list flags)))
  (call-with-message #:data bs
   (λ (m)
     (void
      (retry (λ () (wait s 'POLLOUT))
             (λ () (socket-send-msg-internal! m s (cons 'DONTWAIT flag-list))))))))
(provide/doc
 [proc-doc/names
  socket-send! (->* (socket? bytes?) (#:flags send/recv-flags?) void?)
  ((socket bytes) ((flags '())))
  @{Sends a byte string on a socket using @link["http://api.zeromq.org/4-0:zmq_msg_send"]{zmq_msg_send} with @racket['DONTWAIT] and a temporary message. Does not block other Racket threads.}])

(define-zmq
  [socket-recv-msg! zmq_msg_recv]
  (-> [msg msg?] [socket socket?] [flags send/recv-flags?] void)
  (_fun _msg-pointer _socket _send/recv-flags
        -> [bytes-recvd : _int] -> (when (negative? bytes-recvd) (zmq-error))))

(define-zmq*
  [socket-recv-msg-internal! zmq_msg_recv]
  (_fun _msg-pointer _socket _send/recv-flags -> _int))

(define (socket-recv! s)
  (call-with-message
   (λ (m)
     (retry (λ () (wait s 'POLLIN))
            (λ () (socket-recv-msg-internal! m s 'DONTWAIT)))
     (bytes-copy (msg-data m)))))
(provide/doc
 [proc-doc/names
  socket-recv! (c:-> socket? bytes?)
  (socket)
  @{Receives a byte string on a socket using @link["http://api.zeromq.org/4-0:zmq_msg_recv"]{zmq_msg_recv} with @racket['DONTWAIT] and a temporary message. Does not block other Racket threads.}])

(define-zmq
  [poll! zmq_poll]
  (-> [items (vectorof poll-item?)] [timeout exact-integer?] void)
  (_fun [items : (_vector i _poll-item)] [nitems : _int = (vector-length items)]
        [timeout : _long]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq*
  [proxy* zmq_proxy]
  (_fun _socket _socket _socket/null
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(module+ test
  (require math/base)
  (test-case
   "proxy!"
   (let* ([ctx (context 1)]
          [dealer (socket ctx 'DEALER)])
     (check-exn
      exn:fail:contract?
      (λ ()
        (proxy! dealer #f)))
     (check-exn
      exn:fail:contract?
      (λ ()
        (proxy! #f dealer)))
     (check-exn
      exn:fail:contract?
      (λ ()
        (let ([router (socket ctx 'ROUTER)])
          (dynamic-wind
            void
            (λ ()
               ;; create random number for port
               (let ([port-number (for/fold ([port-number ""])
                                            ([count 4])
                                    (string-append port-number (number->string (random-integer 2 9))))])
                 (socket-connect! router (string-append "tcp://127.0.0.1:" port-number))
                 (socket-bind! dealer "inproc://test-dealers")
                 (proxy! router dealer "shsh")))
            (λ ()
              (socket-close! router))))))
     (socket-close! dealer)
     (context-close! ctx))))

(define (proxy! frontend backend [capture #f])
  (proxy* frontend backend capture))
(provide/doc
 [proc-doc/names
  proxy! (->* (socket/c socket/c) ((or/c socket/c false?)) void)
  ([frontend backend] [(capture #f)])
  @{An FFI binding for @link["http://api.zeromq.org/3-2:zmq_proxy.html"]{zmq_proxy}.
   Given two sockets and an optional capture socket, set up a proxy between
   the frontend socket and the backend socket.}])

(define-zmq
  [zmq-version zmq_version]
  (-> (values exact-nonnegative-integer? exact-nonnegative-integer? exact-nonnegative-integer?))
  (_fun [major : (_ptr o _int)] [minor : (_ptr o _int)] [patch : (_ptr o _int)]
        -> [err : _int] -> (if (zero? err) (values major minor patch) (zmq-error))))
