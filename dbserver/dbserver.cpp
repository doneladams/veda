#include <errno.h>
#include <iostream>
#include <msgpack.hpp>
#include <tarantool/module.h>

#include "dbauth.h"
#include "dbcodes.h"

using namespace std;

#define PUT 1
#define GET 2

#define ACCESS_CAN_CREATE 	(1U << 0)
#define ACCESS_CAN_READ 	(1U << 1)
#define ACCESS_CAN_UPDATE 	(1U << 2)
#define ACCESS_CAN_DELETE 	(1U << 3)

#define MAX_BUF_SIZE 8129 


extern "C" {
	int dbserver_start(lua_State *L);	
	int luaopen_dbserver(lua_State *L);
}


uint32_t individuals_space_id, individuals_index_id;

size_t
get_if_exists(msgpack::object_str &key, char *out_buf)
{
    box_tuple_t *tuple;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);;
    size_t tuple_size;

    pk.pack_array(1);
    pk.pack_str(key.size);
    pk.pack_str_body(key.ptr, key.size);

    box_index_get(individuals_space_id, individuals_index_id, buffer.data(), buffer.data() 
        + buffer.size(), &tuple);

    if (tuple == NULL)
        return 0;

    tuple_size = box_tuple_bsize(tuple);
    box_tuple_to_buf(tuple, out_buf, tuple_size);

    return tuple_size;
}

void
do_put_requet(const char *msg, msgpack::packer<msgpack::sbuffer> &pk)
{

}

void
do_get_requet(const char *msg, msgpack::packer<msgpack::sbuffer> &pk)
{
    size_t msg_size;
    bool need_auth;
    msgpack::unpacker unpk; 
    msgpack::object glob_obj;
    msgpack::object_array obj_arr; 
    msgpack::object_handle result;
    msgpack::object_str user_id;

     
    msg_size = strlen(msg);
    unpk.reserve_buffer(msg_size);
    memcpy(unpk.buffer(), msg, msg_size);
    unpk.buffer_consumed(msg_size);
    unpk.next(result);
    glob_obj = msgpack::object(result.get()); 
    obj_arr = glob_obj.via.array;
    

    if (obj_arr.size < 3) {
        cerr << "Error dbserver: msg arr size less than 2" << endl;
        pk.pack_array(1);
        pk.pack(BAD_REQUEST);
        return;
    }

    pk.pack_array(obj_arr.size * 2);
    need_auth = obj_arr.ptr[0].via.boolean;    
    user_id = obj_arr.ptr[1].via.str;
    if (need_auth)
        cout << "USER ID " << user_id.ptr << endl;

    cout << "NEED AUTH " << need_auth << endl;

    for (int i = 2; i < obj_arr.size; i++) {
        int auth_result = 0;
        char res_buf[MAX_BUF_SIZE];
        size_t res_size;

        msgpack::object_str res_uri;
        res_uri = obj_arr.ptr[i].via.str;
        cout << "RES URI " << res_uri.ptr << endl;
        res_size = get_if_exists(res_uri, res_buf);
        if (res_size > 0) {
            cout << "EXISTS" << endl;
            if (need_auth) 
                auth_result = dbauth(user_id.ptr, user_id.size, res_uri.ptr, res_uri.size);
            cout << "AUTH " << auth_result << endl;
            if ((auth_result & ACCESS_CAN_READ) || !need_auth) {
                pk.pack(OK);
                pk.pack_str(res_size);
                pk.pack_str_body(res_buf, res_size);
            } else {
                pk.pack(AUTH_FAILED);
                pk.pack_nil();
            }
        } else 
            pk.pack(NOT_FOUND);
    }
}

int
dbserver_start(lua_State *L)
{
    uint8_t op;
    const char *msg;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);;

    
    op = lua_tointeger(L, -2);
    msg = lua_tostring(L, -1);
    printf("START SERVER\n");
    printf("op=%d\n", op);

	cout << "@LISTENER STARTED\n" << endl;

	if ((individuals_space_id = box_space_id_by_name("individuals",  
        strlen("individuals"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: individuals" << endl;
		return 0;
	}

    if ((individuals_index_id = box_index_id_by_name(individuals_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH INDEX: primary" << endl;   
        return 0;
    }
    
    switch (op) {
        case GET: {
            printf("GET=%d %s\n", op, msg);
            do_get_requet(msg, pk);
            lua_pushlstring(L, buffer.data(), buffer.size());
            break;
        }
        case PUT: {
            printf("PUT=%d %s\n", op, msg);

        }
    }

    return 1;
}

int 
luaopen_dbserver(lua_State *L)
{
    lua_register(L, "dbserver_start", dbserver_start);  
	return 0;
}