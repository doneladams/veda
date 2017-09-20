./lmdb_to_tarantool ./src-data/lmdb-individuals
tarantoolctl stop init_tarantool.lua
pkill tarantool
