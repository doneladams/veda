#!/bin/bash

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib

ulimit -c unlimited
mkdir logs
mkdir data
mkdir data/tarantool
cp source/rust_db_handler/db_handler/target/release/libdb_handler.so data/tarantool/db_handler.so

tarantool ./source/rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &
#RUST_BACKTRACE=1 tarantool ./source/rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &
#veda-gowebserver/veda-gowebserver >./logs/veda-gowebserver-stdout.log 2>./logs/veda-gowebserver-stderr.log &
/sbin/start-stop-daemon --start --verbose --chdir $PWD --make-pidfile --pidfile $PWD/.veda-pid --background --startas /bin/bash -- -c "exec ./veda >> $PWD/logs/veda-console.log 2>&1"
source/rust_db_handler/graphql/target/debug/graphql >logs/veda-graphql-stdout.log 2>logs/veda-graphql-stderr.log &
