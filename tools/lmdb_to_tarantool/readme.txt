1. Сборка переливщика из lmdb в tarantool:
    dub build

2. Создание пустой базы и запуск tarantool:
    ./create-empty-tarantool-db.sh

3. Копирование lmdb базы данных и очереди uris в папку ./src-data

4. Запуск переливщика:
    ./translate.sh

5.  Готовая база данных располагается в папке data 