rm c_listener.so
clang++ -Wall -L/usr/local/lib -lnanomsg -shared -o c_listener.so -fPIC c_listener.cpp -I/usr/include/lua5.3 
#cp c_listener.so ~/TarantoolVeda/
#cp c_listener.so ../
#cp listener.lua ~/TarantoolVeda/
#cp listener.lua ../
