#!/bin/bash

ulimit -c unlimited
mkdir logs
mkdir data
mkdir data/tarantool
cp db_handler/db_handler.so data/tarantool/

tarantool ./db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &
/sbin/start-stop-daemon --start --verbose --chdir $PWD --make-pidfile --pidfile $PWD/.veda-pid --background --startas /bin/bash -- -c "exec ./veda >> $PWD/logs/veda-console.log 2>&1"
