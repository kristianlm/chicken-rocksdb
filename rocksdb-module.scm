(module rocksdb (rocksdb-open rocksdb-close
                 rocksdb-t           rocksdb-t?
                 rocksdb-iterator-t  rocksdb-iterator-t?
                 rocksdb-put
                 rocksdb-iterator
                 rocksdb-iter-valid?
                 rocksdb-iter-seek
                 rocksdb-iter-next             rocksdb-iter-prev
                 rocksdb-iter-key              rocksdb-iter-value

                 rocksdb-iter-destroy

                 rocksdb-writebatch-t?
                 rocksdb-writebatch
                 rocksdb-writebatch-put
                 rocksdb-writebatch-clear
                 rocksdb-writebatch-destroy
                 rocksdb-write

                 rocksdb-compact-range

                 ;; ========== unofficial, in case I've got all this wrong:
                 rocksdb-iter-next*            rocksdb-iter-prev*
                 rocksdb-iter-key*             rocksdb-iter-value*
                 rocksdb-iter-seek*
                 )
(import scheme chicken.base)
(include "rocksdb.scm")
)
