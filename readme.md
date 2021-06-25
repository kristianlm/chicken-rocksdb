
  [RocksDB]: http://rocksdb.org "RocksDB"
  [CHICKEN Scheme]: http://call-cc.org "CHICKEN Scheme"

# [RocksDB] bindings for [CHICKEN Scheme] 5

Only a portion of the comprehensive RocksDB API is currently
exposed. However, the API covered by this egg should hopefully get
most projects started.

This egg has been tested on [RocksDB] 6.15 and 5.8.

An aim of this project is to expose the [RocksDB] API as-is as much as
possible. Some exceptions include `rocksdb_open_for_read_only` being
embedded in `rocksdb-open`, and naming conventions turning
`rocksdb_writebatch_create` into `rocksdb-writebatch`, for example.

# API

    [procedure] (rocksdb-open name #!key read-only (compression 'lz4) (create-if-missing #t) paranoid-checks (finalizer rocksdb-close)) => rocksdb-t

Opens database at path `name`, returning a `rocksdb-t` object. Setting
`read-only` to a non-false value, will call
`rocksdb_open_for_read_only` instead of `rocksdb_open`. This is useful
as multiple OS processes may open a database in read-only mode, but
only one may open for read-write.

`compression` must be one of `(#f snappy zlib bz2 lz4 lz4hc xpress
zstd)`. `create-if-missing` and `paranoid-checks` are applied as-is to
the C API.

    [procedure] (rocksdb-close db)

Closes `db`. It is safe to call this multiple times. This does not
normally need to be called explicitly as it is the default finalizer
specified in `rocksdb-open`.

    [procedure] (rocksdb-put db key value #!key (sync #f) (wal #t))

Inserts a pair into `db`. `key` and `value` must both be strings or
chicken.blobs.

For the `sync` and `wal` (parameters, see the original [C
documentation](https://github.com/facebook/rocksdb/blob/v6.15.5/include/rocksdb/options.h#L1434).

Note that if you want to insert a lot of data, writebatch may be a
better approach as it's probably going to be faster.


    [procedure] (rocksdb-iterator db #!key seek verify-checksums fill-cache read-tier tailing readahead-size pin-data total-order-seek (finalizer rocksdb-iter-destroy)) => rocksdb-iterator-t

Create a `rocksdb-iterator-t` instance which you can use to seek, and
read keys and values from `db`.

    [procedure] (rocksdb-iter-valid? it)

Returns `#t` if `it` is in a valid position (where you can read keys
and move it back or forwards). If this returns `#f` and you call
`rocksdb-iter-next` for example, this may segfault.

    [procedure] (rocksdb-iter-seek-to-first it)
    [procedure] (rocksdb-iter-seek-to-last it)
    [procedure] (rocksdb-iter-seek it key)

Move `it` to the absolute position specified. `key` must be a string
or chicken.blob.

    [procedure] (rocksdb-iter-next it)
    [procedure] (rocksdb-iter-prev it)

Move `it` forward or backward one step. Note that
`rocksdb-iter-valid?` must return `#t` for this operation to be safe.

    [procedure] (rocksdb-iter-key it)
    [procedure] (rocksdb-iter-value it)

Get the current `key` or `value` for `it` at its current position.
Note that `rocksdb-iter-valid?` must return `#t` for this operation to
be safe. The current implementation copies the foreign memory into a
CHICKEN string which may not be ideal for large objects.

    [procedure] (rocksdb-iter-destroy)

Free the `rocksdb_t` structure held by this record. It is safe to call
this multiple times. It does normally not need to be called as it's
the default finalizer specified in `rocksdb-iterator`.

    [procedure] (rocksdb-writebatch #!key (finalizer rocksdb-writebatch-destroy)) => rocksdb-writebatch-t

A writebatch is an object which can hold key-value pairs temporarily,
for later to quickly be inserted to a `rocksdb-t` instance.

    [procedure] (rocksdb-writebatch-put wb key value)

Insert a pair into `wb`. `key` and `value` must be strings or
chicken.blobs. Unless data is persisted to a database with
`rocksdb-write`, data held by a writebatch is not persisted anywhere.

    [procedure] (rocksdb-writebatch-clear wb)

Remove all entries in `wb` inserted by `rocksdb-writebatch-put`,
making it available for re-use.

    [procedure] (rocksdb-writebatch-destroy wb)

Free the `wb` object and its foreign memoryd. This does not normally
need to be called explicitly as it's the default finalizer in
`rocksdb-writebatch`.

    [procedure] (rocksdb-write db wb #!key (sync #f) (wal #t))

Write all the entries of `wb` into `db`, persisting them on disk. See
`rocksdb-put` for the `sync` and `wal` argument options.

    [procedure] (rocksdb-compact-range db start limit #!key exclusive change-level (target-level 0))

Run a database compaction, hopefully reducing the consumed disk
space. `start` and `limit` are keys that specify the range of keys to
run the compaction for. Both may be `#f` to specify all keys in the
database.

See the original [C
documentation](https://github.com/facebook/rocksdb/blob/v6.15.5/include/rocksdb/options.h#L1566)
for usages of the remainding parameters.

# TODO

- add the column family API
- add the backup API
- add the transaction API
- add the merge API (hard, probably needs callbacks)
- add support for custom comparators (hard, probably needs callbacks)
- add the sstfilewriter API
