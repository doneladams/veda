#!/bin/bash

for (( i=1; i <= 320; i++ ))
do

./queue2tarantool 1 5 1000000 no_check &
PID1=$!
./queue2tarantool 2 5 1000000 no_check &
PID2=$!
./queue2tarantool 3 5 1000000 no_check &
PID3=$!
./queue2tarantool 4 5 1000000 no_check &
PID4=$!
./queue2tarantool 5 5 1000000 no_check &
PID5=$!

#sudo tarantoolctl restart veda_app
wait $PID1
wait $PID2
wait $PID3
wait $PID4
wait $PID5

done
