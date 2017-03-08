package main

import (
	"fmt"

	"log"

	nanomsg "github.com/op/go-nanomsg"
)

// #cgo CFLAGS: -I/usr/include/lua5.3
// #cgo LDFLAGS: -llua5.3 -L/usr/local/lib -ltarantool -Wl,-unresolved-symbols=ignore-all
// #include <tarantool/module.h>
// extern int golistener_start();
import "C"

var aclSpaceId, aclIndexId C.uint32_t

//export golistener_start
func golistener_start(L *C.lua_State) C.int {
	fmt.Println("@GOLISTENER START")

	individualsSpaceID := C.box_space_id_by_name(C.CString("individuals"),
		C.uint32_t(len("individuals")))
	if individualsSpaceID == C.BOX_ID_NIL {
		log.Printf("LISTENER: Error on getting individuals space id")
		return C.int(0)
	}

	socket, err := nanomsg.NewSocket(nanomsg.AF_SP, nanomsg.PAIR)
	if err != nil {
		log.Println("LISTENER: Error on creating socket: ", err)
		return C.int(0)
	}

	_, err = socket.Bind("tcp://127.0.0.1:9090")
	if err != nil {
		log.Println("LISTENER: Error on binding socket: ", err)
		return C.int(0)
	}

	for {
		msgpack, err := socket.Recv(0)
		if err != nil {
			log.Println("LISTENER: Error on reading socket: ", err)
			return C.int(0)
		}
		fmt.Println(string(msgpack[:]))
	}

	return C.int(0)
}

//export luaopen_golistener
func luaopen_golistener(L *C.lua_State) int {
	fmt.Println("TRY TO PUSH FUNC")
	C.lua_pushcclosure(L, (*[0]byte)(C.golistener_start), 0)
	fmt.Println("TRY TO SET GLOBAL")
	C.lua_setfield(L, C.LUA_GLOBALSINDEX, C.CString("golistener_start"))
	return 0
}

func main() {

}
