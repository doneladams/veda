#!/bin/bash

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib

ulimit -c unlimited
mkdir logs
mkdir data
mkdir data/tarantool
cp rust_db_handler/db_handler/target/release/libdb_handler.so data/tarantool/db_handler.so

tarantool ./rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &
veda-gowebserver/veda-gowebserver >./logs/veda-gowebserver-stdout.log 2>./logs/veda-gowebserver-stderr.log &
/sbin/start-stop-daemon --start --verbose --chdir $PWD --make-pidfile --pidfile $PWD/.veda-pid --background --startas /bin/bash -- -c "exec ./veda >> $PWD/logs/veda-console.log 2>&1"
