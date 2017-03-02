CC = clang++
CFLAGS = `pkg-config --cflags msgpack`
CFLAGS += -Wall -Wno-dangling-else  -std=c++11 -shared
CFLAGS += -fPIC -I/usr/include/lua5.3
LIBS = `pkg-config --libs msgpack`  -L/usr/local/lib -lnanomsg
C_LISTENER_SRC = c_listener.cpp individual.cpp
C_LISTENER_OUT = c_listener.so

all: 
	$(CC) $(CFLAGS) $(LIBS) -o $(C_LISTENER_OUT) $(C_LISTENER_SRC)