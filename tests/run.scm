(import test rocksdb chicken.file chicken.port)

(if (directory-exists? "test.rocks")
    (delete-directory "test.rocks" #t))

(test-group
 "rocksdb-open"

 (test-error (rocksdb-open "test.rocks" create-if-missing: #f))

 (define db (rocksdb-open "test.rocks"))
 (test #t (rocksdb-t? db))
 (test "rocksdb-close is idempotent" (void) (rocksdb-close db))
 (test "rocksdb-close is idempotent" (void) (rocksdb-close db))

 (define db (rocksdb-open "test.rocks"))

 (rocksdb-put db "a" "1")
 (rocksdb-put db "b" "2")
 (rocksdb-put db "c" "3")

 (test-group
  "rocksdb-iterator"

  (define it (rocksdb-iterator db))
  (test #t (rocksdb-iterator-t? it))
  (test #f (rocksdb-iter-valid? it))

  (rocksdb-iter-seek it 'first)
  (test "a" (rocksdb-iter-key it)) (test "1" (rocksdb-iter-value it))
  
  (rocksdb-iter-next it)       (test "next" "b" (rocksdb-iter-key it))
  (rocksdb-iter-seek it "c")   (test "seek" "c" (rocksdb-iter-key it))
  (rocksdb-iter-prev it)       (test "prev" "b" (rocksdb-iter-key it))
  (rocksdb-iter-seek it 'last) (test "last" "c" (rocksdb-iter-key it))

  (test "#<rocksdb-iterator-t \"c\">" (with-output-to-string (lambda () (display it))))
  (rocksdb-iter-next it)
  (test "invalid it after \"c\"" #f (rocksdb-iter-valid? it))
  (test "no key"   #f (rocksdb-iter-key it))
  (test "no value" #f (rocksdb-iter-value it))

  (test-group
   "rocksdb-iterator args"
   (define it (rocksdb-iterator db seek: "b"))
   (test "b" (rocksdb-iter-key it))
   (test "explicitly destroyable" (begin) (rocksdb-iter-destroy it)))

  (test-group
   "rocksdb writebatch"

   (define put rocksdb-writebatch-put)
   (define wb (rocksdb-writebatch))
   (test #t (rocksdb-writebatch-t? wb))

   (put wb "hello" "")
   (put wb "from" "")
   (put wb "wb" "")

   (test "explicit call to rocksdb-writebatch-destroy" (begin) (rocksdb-writebatch-destroy wb))

   ))

 (test-group
  "tailing"
  (define it (rocksdb-iterator db tailing: #t))
  (rocksdb-iter-seek it 'first)
  (rocksdb-put db "!" "post-iterator entry")
  (rocksdb-iter-seek it 'first)
  (test "!" (rocksdb-iter-key it))
  (test "post-iterator entry" (rocksdb-iter-value it)))

 (test-group
  "compaction range"
  (rocksdb-compact-range db "a" "b")
  (rocksdb-compact-range db #f #f)))
