#include <arpa/inet.h>
#include <errno.h>
#include <strings.h>
#include <signal.h>
#include <nanomsg/nn.h>
#include <nanomsg/pair.h>
#include <tarantool/module.h>
#include <unistd.h>
#include <sys/time.h>

#define MP_SOURCE 1

#include "msgpuck.h"

int
c_listener_start(lua_State *L)
{
	uint32_t individuals_space_id;
	int socket_fd;

	if ((individuals_space_id = box_space_id_by_name("individuals", 
		strlen("individuals"))) == BOX_ID_NIL) {
		fprintf(stderr, "No such space");
		return 0;
	}
	
	if ((socket_fd = nn_socket(AF_SP, NN_PAIR)) < 0) {
		fprintf(stderr, "LISTENER: Error on creating socket: %s\n", nn_strerror(errno));
		return 0;
	}

	if ((nn_bind (socket_fd, "tcp://127.0.0.1:9090")) < 0) {
		fprintf(stderr, "LISTENER: Error on binding socket: %s\n", nn_strerror(errno));
		return 1;
	}
			
	for (;;	) {
		char *msgpack;
		ssize_t size;

		msgpack = NULL;
		size = nn_recv(socket_fd, &msgpack, NN_MSG, 0);
		printf("GOT MSGPACK %s\n", msgpack);
		if (box_replace(individuals_space_id, msgpack, msgpack + size, NULL) < 0) {
			fprintf(stderr, "LISTENER: Error on inserting msgpack %s\n", msgpack);
			nn_close(socket_fd);
			return 0;
		}
		
		nn_freemsg(msgpack);
	}
	
	nn_close(socket_fd);			
	return 1;
}

int 
luaopen_c_listener(lua_State *L)
{
	lua_register(L, "c_listener_start", c_listener_start);  
	return 0;
}