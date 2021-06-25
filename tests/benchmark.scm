;;; inserts a lot of tiny entries into benchmark.rocks as quickly as
;;; possible.
;;;
;;; csi -s tests/benchmark.scm | pv -l >/dev/null
;;;
;;; I'm getting ~500k/s, you? #:wal seems to have little effect, bug?
;;;
(import rocksdb chicken.string)

(define db (rocksdb-open "benchmark.rocks"))
(define wb (rocksdb-writebatch))

(define commit!
  (let ((count 0))
    (lambda (force?)
      (set! count (+ 1 count))
      (when (or force? (>= count 1000))
        (set! count 0)
        (rocksdb-write db wb sync: #f wal: #f)
        (rocksdb-writebatch-clear wb)))))

(let loop ((n 10000000))
  (when (> n 0)
    (rocksdb-writebatch-put wb (conc "n" n) (conc "v" n))
    (commit! #f)
    (print n)
    (loop (- n 1))))

(commit! #t)
