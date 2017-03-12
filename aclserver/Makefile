CC = clang++
CFLAGS = `pkg-config --cflags msgpack`
CFLAGS += -Wall -Wno-dangling-else  -std=c++11 -shared
CFLAGS += -fPIC -I/usr/include/lua5.3
LIBS = `pkg-config --libs msgpack`  -L/usr/local/lib -lnanomsg
ACLSERVER_SRC= aclserver.cpp aclauth.cpp
ACLSERVER_OUT = aclserver.so

all: 
	$(CC) $(CFLAGS) $(LIBS) -o $(ACLSERVER_OUT) $(ACLSERVER_SRC)