rm c_listener.so
clang -Wall -lnanomsg -shared -o c_listener.so -fPIC c_listener.c -I/usr/include/lua5.3 
cp c_listener.so ~/TarantoolVeda/
cp listener.lua ~/TarantoolVeda/
