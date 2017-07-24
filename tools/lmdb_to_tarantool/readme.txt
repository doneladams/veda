Сборка переливщика из lmdb в tarantool:
    dub build

Сборка модуля на rust:
    cd ..
    ./build.sh db_handler

Запуск tarantool:
    mkdir logs
    mkdir data
    mkdir data/tarantool

    cp source/rust_db_handler/db_handler/target/release/libdb_handler.so data/tarantool/db_handler.so
    tarantool ./source/rust_db_handler/init_tarantool.lua 2>./logs/tarantool-stderr.log  >./logs/tarantool-stdout.log &

***

cd tools/lmdb_to_tarantool

Запуск переливщика:
    ./lmdb_to_tarantool /path/to/file