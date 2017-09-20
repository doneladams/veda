mkdir logs
mkdir data
mkdir data/tarantool
mkdir src-data

cp ../../source/rust_db_handler/db_handler/target/release/libdb_handler.so data/tarantool/db_handler.so
tarantool ../../source/rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &

