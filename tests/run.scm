(import test rocksdb chicken.file chicken.port)

(if (directory-exists? "testdb")
    (delete-directory "testdb" #t))

(test-group
 "rocksdb-open"

 (test-error (rocksdb-open "testdb" create-if-missing: #f))

 (define db (rocksdb-open "testdb"))
 (test #t (rocksdb-t? db))
 (test "rocksdb-close is idempotent" (void) (rocksdb-close db))
 (test "rocksdb-close is idempotent" (void) (rocksdb-close db))

 (define db (rocksdb-open "testdb"))
 
 (rocksdb-put db "a" "1")
 (rocksdb-put db "b" "2")
 (rocksdb-put db "c" "3")

 (test-group
  "rocksdb-iterator"

  (define it (rocksdb-iterator db))
  (test #t (rocksdb-iterator-t? it))
  (test #f (rocksdb-iter-valid? it))
  
  (rocksdb-iter-seek-to-first it)  (test #t (rocksdb-iter-valid? it)) (test "a" (rocksdb-iter-key it)) (test "1" (rocksdb-iter-value it))
  (rocksdb-iter-next it)           (test #t (rocksdb-iter-valid? it)) (test "b" (rocksdb-iter-key it)) (test "2" (rocksdb-iter-value it))
  (rocksdb-iter-seek it "c")       (test #t (rocksdb-iter-valid? it)) (test "c" (rocksdb-iter-key it)) (test "3" (rocksdb-iter-value it))

  (test "#<rocksdb-iterator-t \"c\">" (with-output-to-string (lambda () (display it))))
  (rocksdb-iter-next it)
  (test #f (rocksdb-iter-valid? it))

  (rocksdb-iter-seek it "a") (test "a" (rocksdb-iter-key it))
  (rocksdb-iter-prev it)
  (test #f (rocksdb-iter-valid? it))

  (test-group
   "rocksdb-iterator args"
   (define it (rocksdb-iterator db seek: "b"))
   (test "b" (rocksdb-iter-key it)))

  (test-group
   "rocksdb writebatch"

   (define put rocksdb-writebatch-put)
   (define wb (rocksdb-writebatch))
   (test #t (rocksdb-writebatch-t? wb))

   (put wb "hello" "")
   (put wb "from" "")
   (put wb "wb" "")

   ))

 (test-group
  "compaction range"
  (rocksdb-compact-range db "a" "b")
  (rocksdb-compact-range db #f #f)))


