(module rocksdb (rocksdb-open rocksdb-close
                 rocksdb-t           rocksdb-t?
                 rocksdb-iterator-t  rocksdb-iterator-t?
                 rocksdb-put
                 rocksdb-iterator
                 rocksdb-iter-valid?
                 rocksdb-iter-seek-to-first    rocksdb-iter-seek-to-last       rocksdb-iter-seek
                 rocksdb-iter-next             rocksdb-iter-prev
                 rocksdb-iter-key              rocksdb-iter-value

                 rocksdb-writebatch-t?
                 rocksdb-writebatch
                 rocksdb-writebatch-put
                 rocksdb-writebatch-clear
                 rocksdb-write)
(import scheme chicken.base)
(include "rocksdb.scm")
)
