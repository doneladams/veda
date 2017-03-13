CC = clang++
CFLAGS = `pkg-config --cflags msgpack`
CFLAGS += -Wall -Wno-dangling-else  -std=c++11 -shared
CFLAGS += -fPIC -I/usr/include/lua5.3
LIBS = `pkg-config --libs msgpack`  -L/usr/local/lib -lnanomsg
DBSERVER_SRC= dbserver.cpp dbauth.cpp
DBSERVER_OUT = dbserver.so

all: 
	$(CC) $(CFLAGS) $(LIBS) -o $(DBSERVER_OUT) $(DBSERVER_SRC)