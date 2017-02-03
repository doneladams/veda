rm authorize.so
gcc -Wall -shared -o authorize.so -fPIC authorize_lua_cache.c -I/usr/include/lua5.3
cp test_auth.lua ~/tntbase2/
cp authorize.so ~/tntbase2/