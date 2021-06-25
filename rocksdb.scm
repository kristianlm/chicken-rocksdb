(import chicken.foreign
        chicken.gc
        chicken.condition
        (only chicken.string conc)
        (only chicken.memory move-memory! free)
        (only chicken.memory.representation number-of-bytes))

(foreign-declare "#include <rocksdb/c.h>")

(define-record rocksdb-t pointer)
(define-foreign-type rocksdb (c-pointer "rocksdb_t")
  (lambda (rocksdb) (rocksdb-t-pointer rocksdb))
  (lambda (pointer) (make-rocksdb-t pointer)))
(define-record-printer rocksdb-t
  (lambda (db port)
    (display "#<rocksdb-t " port)
    (display (rocksdb-t-pointer db) port)
    (display ">" port)))

(define-record rocksdb-iterator-t pointer)
(define-foreign-type rocksdb-iterator (c-pointer "rocksdb_iterator_t")
  (lambda (it) (rocksdb-iterator-t-pointer it))
  (lambda (pointer) (make-rocksdb-iterator-t pointer)))
(define-record-printer rocksdb-iterator-t
  (lambda (it port)
    (display "#<rocksdb-iterator-t" port)
    (if (rocksdb-iter-valid? it)
        (let* ((key (rocksdb-iter-key it))
               (len (string-length key))
               (key (if (> len 32)
                        (conc (substring key 0 32) "…")
                        key)))
          (display " " port)
          (write key port)))
    (display ">" port)))


(define-record rocksdb-writebatch-t pointer)
(define-foreign-type rocksdb-writebatch (c-pointer "rocksdb_writebatch_t")
  (lambda (it) (rocksdb-writebatch-t-pointer it))
  (lambda (pointer) (make-rocksdb-writebatch-t pointer)))
(define-record-printer rocksdb-writebatch-t
  (lambda (db port)
    (display "#<rocksdb-writebatch-t " port)
    (display (rocksdb-writebatch-t-pointer db) port)
    (display ">" port)))

;; call thunk with error string pointer, signalling exception if it's
;; non-null after call.
(define (call-with-errptr thunk)
  (let-location ((err* (c-pointer c-string) #f))
    (let ((result (thunk (location err*))))
      (if err*
          ;;                               ,-- copy error message & free
          (let* ((err ((foreign-lambda* c-string (((c-pointer c-string) err)) "return(err);") err*))
                 (_   (free err*)))
            (abort
             (make-composite-condition
              (make-property-condition 'exn 'message err)
              (make-property-condition 'rocksdb))))
          result))))

(define (rocksdb-close db)
  ;; (print "» rocksdb-close " db)
  (when (rocksdb-t-pointer db)
    ((foreign-lambda void "rocksdb_close" rocksdb) db)
    (rocksdb-t-pointer-set! db #f)))

(define (<->compression compression)
  (let ((alst
         `((#f     . ,(foreign-value "rocksdb_no_compression" int))
           (snappy . ,(foreign-value "rocksdb_snappy_compression" int))
           (zlib   . ,(foreign-value "rocksdb_zlib_compression" int))
           (bz2    . ,(foreign-value "rocksdb_bz2_compression" int))
           (lz4    . ,(foreign-value "rocksdb_lz4_compression" int))
           (lz4hc  . ,(foreign-value "rocksdb_lz4hc_compression" int))
           (xpress . ,(foreign-value "rocksdb_xpress_compression" int))
           (zstd   . ,(foreign-value "rocksdb_zstd_compression" int)))))
    (or (alist-ref compression alst)
        (error (conc "compression not found in " (map car alst)) compression))))

(define (rocksdb-open name #!key
                      (finalize #t)
                      (read-only #f)
                      (compression 'lz4)
                      (create-if-missing #t)
                      (paranoid-checks #f))
  (let* ((open* (foreign-lambda* rocksdb ((c-string name)
                                          (bool read_only)
                                          ;; options
                                          (int compression)
                                          (bool create_if_missing)
                                          (bool paranoid_checks)
                                          ((c-pointer c-string) errptr))
                                 "
rocksdb_options_t *o = rocksdb_options_create();
rocksdb_options_set_compression(o, compression);
rocksdb_options_set_create_if_missing(o, create_if_missing);
rocksdb_options_set_paranoid_checks(o, paranoid_checks);
rocksdb_t *db;
if(read_only) {
 db = rocksdb_open_for_read_only(o, name, 1, errptr);
} else {
 db = rocksdb_open(o, name, errptr);
}
rocksdb_options_destroy(o);
return(db);
"))
         (db (call-with-errptr
              (cut open* name
                   read-only
                   (<->compression compression)
                   create-if-missing
                   paranoid-checks
                   <>))))
    (when finalize (set-finalizer! db rocksdb-close))
    db))

(define (rocksdb-put db key value #!key
                     (sync #f)
                     (wal #t))
  (let* ((put* (foreign-lambda* void ((rocksdb db)
                                      (scheme-pointer key)
                                      (size_t keylen)
                                      (scheme-pointer value)
                                      (size_t vallen)
                                      (bool sync)
                                      (bool wal)
                                      ((c-pointer c-string) errptr)) "
rocksdb_writeoptions_t *o = rocksdb_writeoptions_create();
rocksdb_writeoptions_set_sync(o, sync);
rocksdb_writeoptions_disable_WAL(o, !wal);
rocksdb_put(db, o, key, keylen, value, vallen, errptr);
rocksdb_writeoptions_destroy(o);
")))
    (call-with-errptr
     (cut put*
          db
          key   (number-of-bytes key)
          value (number-of-bytes value)
          sync
          wal
          <>))))

(define (rocksdb-iter-destroy it)
  (when (rocksdb-iterator-t-pointer it)
    ((foreign-lambda void "rocksdb_iter_destroy" rocksdb-iterator) it)
    (rocksdb-iterator-t-pointer-set! it #f)))

(define (rocksdb-iterator db #!key
                          (finalize #t)
                          (seek #f)
                          ;; ==================== options ====================
                          (verify-checksums #t)
                          (fill-cache #t)
                          ;; snapshot
                          ;; key, size_t keylen iterate-upper-bound
                          (read-tier 0)
                          (tailing #f)
                          (readahead-size 0) ;; <-- defaults to 8k, I think
                          pin-data
                          total-order-seek)
  (let* ((iterator*
          (foreign-lambda* rocksdb-iterator ((rocksdb db)
                                             (bool verify_checksums)
                                             (bool fill_cache)
                                             ;;(rocksdb_snapshot_t* snapshot())
                                             ;;(char* key, size_t keylen iterate_upper_bound)
                                             (int read_tier)
                                             (bool tailing)
                                             (size_t readahead_size)
                                             (bool pin_data)
                                             (bool total_order_seek)
                                             ((c-pointer c-string) errptr))
                           "  
rocksdb_readoptions_t* ro = rocksdb_readoptions_create();
rocksdb_readoptions_set_verify_checksums(ro, verify_checksums);
rocksdb_readoptions_set_fill_cache(ro, fill_cache);
// rocksdb_readoptions_set_snapshot(ro, snapshot);
// rocksdb_readoptions_set_iterate_upper_bound(ro, key, size_t keylen);
rocksdb_readoptions_set_read_tier(ro, read_tier);
rocksdb_readoptions_set_tailing(ro, tailing);
rocksdb_readoptions_set_readahead_size(ro, readahead_size);
rocksdb_readoptions_set_pin_data(ro, pin_data);
rocksdb_readoptions_set_total_order_seek(ro, total_order_seek);

rocksdb_iterator_t *it = rocksdb_create_iterator(db, ro);

rocksdb_readoptions_destroy(ro);
return(it);
"))
         (it
          (call-with-errptr
           (cut iterator*
                db
                verify-checksums
                fill-cache
                ;; snapshot
                ;; key, size_t keylen iterate-upper-bound
                read-tier
                tailing
                readahead-size
                pin-data
                total-order-seek
                <>))))
    (when finalize (set-finalizer! it rocksdb-iter-destroy))
    (when seek
      (cond ((equal? seek 0) (rocksdb-iter-seek-to-first it))
            ((equal? seek 1) (rocksdb-iter-seek-to-last it))
            ((string? seek) (rocksdb-iter-seek it seek))
            (else (error "unknown seek value (expecting 0/1 for first/last or string), got: " seek))))
    it))

(define rocksdb-iter-valid?        (foreign-lambda bool "rocksdb_iter_valid" rocksdb-iterator))
(define rocksdb-iter-seek-to-first (foreign-lambda void "rocksdb_iter_seek_to_first" rocksdb-iterator))
(define rocksdb-iter-seek-to-last  (foreign-lambda void "rocksdb_iter_seek_to_first" rocksdb-iterator))
(define rocksdb-iter-next          (foreign-lambda void "rocksdb_iter_next" rocksdb-iterator))
(define rocksdb-iter-prev          (foreign-lambda void "rocksdb_iter_prev" rocksdb-iterator))

(define (rocksdb-iter-seek it key)
  ((foreign-lambda void "rocksdb_iter_seek" rocksdb-iterator scheme-pointer size_t)
   it key (number-of-bytes key)))

(define (rocksdb-iter-key it)
  (let-location ((len size_t))
    (let ((str* ((foreign-lambda (c-pointer char) "rocksdb_iter_key" rocksdb-iterator (c-pointer size_t))
                 it (location len)))
          (str (make-string len)))
      (move-memory! str* str len)
      str)))

(define (rocksdb-iter-value it)
  (let-location ((len size_t))
    (let ((str* ((foreign-lambda (c-pointer char) "rocksdb_iter_value" rocksdb-iterator (c-pointer size_t))
                 it (location len)))
          (str (make-string len)))
      (move-memory! str* str len)
      str)))


;; ==================== writebatch ====================

(define (rocksdb-writebatch-destroy writebatch)
  ((foreign-lambda void "rocksdb_writebatch_destroy" rocksdb-writebatch)
   writebatch)
  (rocksdb-writebatch-t-pointer-set! writebatch #f))

(define rocksdb-writebatch-clear   (foreign-lambda void "rocksdb_writebatch_clear" rocksdb-writebatch))

(define (rocksdb-writebatch #!key (finalize #t))
  (let ((wb ((foreign-lambda rocksdb-writebatch "rocksdb_writebatch_create"))))
    (when finalize
      (set-finalizer! wb rocksdb-writebatch-destroy))
    wb))

(define (rocksdb-writebatch-put writebatch key value) ;;                            key       keylen      value     vallen
  ((foreign-lambda void "rocksdb_writebatch_put" rocksdb-writebatch scheme-pointer size_t scheme-pointer size_t)
   writebatch
   key   (number-of-bytes key)
   value (number-of-bytes value)))

(define (rocksdb-write db writebatch #!key
                       (sync #f)
                       (wal #t))
  (let* ((write* (foreign-lambda* void ((rocksdb db)
                                        (rocksdb-writebatch writebatch)
                                        (bool sync)
                                        (bool wal)
                                        ((c-pointer c-string) errptr)) "
rocksdb_writeoptions_t *o = rocksdb_writeoptions_create();
rocksdb_writeoptions_set_sync(o, sync);
rocksdb_writeoptions_disable_WAL(o, !wal);
rocksdb_write(db, o, writebatch, errptr);
rocksdb_writeoptions_destroy(o);
")))
    (call-with-errptr
     (cut write* db writebatch sync wal <>))))

;; ==================== compaction_range ====================


(define (rocksdb-compact-range db start limit #!key
                               exclusive
                               change-level
                               (target-level 0))
   ((foreign-lambda* void ((rocksdb db)
                          (scheme-pointer start)
                          (size_t start_len)
                          (scheme-pointer limit)
                          (size_t limit_len)
                          (bool exclusive)
                          (bool change_level)
                          (int target_level)
                          ) "
rocksdb_compactoptions_t *o = rocksdb_compactoptions_create();
rocksdb_compactoptions_set_exclusive_manual_compaction(o, exclusive);
rocksdb_compactoptions_set_change_level(o, change_level);
rocksdb_compactoptions_set_target_level(o, target_level);
rocksdb_compact_range_opt(db, o, start, start_len, limit, limit_len);
rocksdb_compactoptions_destroy(o);
")
   db
   start (if start (number-of-bytes start) 0)
   limit (if limit (number-of-bytes limit) 0)
   exclusive change-level target-level))
