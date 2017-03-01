#!/bin/bash

ulimit -c unlimited
mkdir logs
mkdir data
mkdir data/tarantool
cp tarantool/c_listener.so data/tarantool/
cp tarantool/listener.lua data/tarantool/
tarantool ./tarantool/init_tarantool.lua &

/sbin/start-stop-daemon --start --verbose --chdir $PWD --make-pidfile --pidfile $PWD/.veda-pid --background --startas /bin/bash -- -c "exec ./veda >> $PWD/logs/veda-console.log 2>&1"
