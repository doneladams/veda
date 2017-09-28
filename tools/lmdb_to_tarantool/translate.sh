# start tarantool
tarantool ../../source/rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &
# start translate
./lmdb_to_tarantool ./src-data/lmdb-individuals
# stop tarantool
tarantoolctl stop init_tarantool.lua
pkill tarantool
