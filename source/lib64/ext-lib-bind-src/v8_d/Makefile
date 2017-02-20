CC=g++
INCLUDES=`pkg-config --cflags msgpack`
LIBS=`pkg-config --libs msgpack`
CFLAGS=$(INCLUDES) $(LIBS) -g -c -Wl,--start-group msgpack8individual.cpp v8d.cc

all:
	g++ $(CFLAGS) msgpack8individual.cpp v8d.cc    
	ar rvs libv8d.a *.o
	rm *.o
	mv libv8d.a ../../
