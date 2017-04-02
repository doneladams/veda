CC = clang++
CFLAGS = `pkg-config --cflags msgpack`
CFLAGS += -Wall -Wno-dangling-else  -std=c++11 -shared
CFLAGS += -fPIC -I/usr/include/lua5.3
LIBS = `pkg-config --libs msgpack`
DB_HANDLER_SRC= db_handler.cpp db_auth.cpp db_remove.cpp db_get.cpp db_put.cpp individual.cpp
DB_HANDLER_OUT = db_handler.so

all: 
	$(CC) $(CFLAGS) $(LIBS) -o $(DB_HANDLER_OUT) $(DB_HANDLER_SRC)