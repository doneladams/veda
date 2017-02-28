#!/bin/bash

ulimit -c unlimited
mkdir logs
mkdir data
/sbin/start-stop-daemon --start --verbose --chdir $PWD --make-pidfile --pidfile $PWD/.veda-pid --background --startas /bin/bash -- -c "exec ./veda >> $PWD/logs/veda-console.log 2>&1"
cp c_listener.so data/
cp listener.lua data/
tarantool init_tarantool.lua &