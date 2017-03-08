package main

import "fmt"

// #cgo CFLAGS: -I/usr/include/lua5.3
// #cgo LDFLAGS: -llua5.3
// #include <lua.h>
// extern int test_lib_start();
import "C"

//export dummy
func dummy() C.int {
	return C.int(0)
}

//export test_lib_start
func test_lib_start(L *C.lua_State) C.int {
	fmt.Println("@GOLISTENER START")
	return C.int(0)
}

//export luaopen_test_lib
func luaopen_test_lib(L *C.lua_State) int {
	// C.lua_register(L, "golistener_start", C.dummy)
	C.lua_pushcclosure(L, (*[0]byte)(C.test_lib_start), 0)
	C.lua_setglobal(L, C.CString("test_lib_start"))
	return 0
}

func main() {

}
