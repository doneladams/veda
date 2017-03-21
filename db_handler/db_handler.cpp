#include <errno.h>
#include <iostream>
#include <msgpack.hpp>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_put.h"

using namespace std;

#define PUT 1
#define GET 2

#define ACCESS_CAN_CREATE 	(1U << 0)
#define ACCESS_CAN_READ 	(1U << 1)
#define ACCESS_CAN_UPDATE 	(1U << 2)
#define ACCESS_CAN_DELETE 	(1U << 3)

#define MAX_BUF_SIZE 8129 


extern "C" {
	int db_handle_request(lua_State *L);	
	int luaopen_db_handler(lua_State *L);
}


uint32_t individuals_space_id, individuals_index_id;
uint32_t acl_space_id, acl_index_id;
uint32_t rdf_types_space_id, rdf_types_index_id;

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
handle_put_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk)
{
    bool need_auth;
    msgpack::unpacker unpk; 
    msgpack::object glob_obj;
    msgpack::object_array obj_arr; 
    msgpack::object_handle result;
    msgpack::object_str user_id;

     
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
    printf("OBJ ARR SIZE=%u\n", obj_arr.size);

    pk.pack_array(obj_arr.size - 1);
    need_auth = obj_arr.ptr[0].via.boolean;    
    user_id = obj_arr.ptr[1].via.str;
    cout << "MSG " << msg << endl;
    if (need_auth)
        cout << "USER ID " << user_id.ptr << endl;

    printf("NEED AUTH %d\n", need_auth);
    pk.pack(OK);
    for (uint32_t i = 2; i < obj_arr.size; i++) {
        msgpack::object_str indiv_msgpack;
        // printf("size=%u i=%u\n", obj_arr.size, i);
        indiv_msgpack = obj_arr.ptr[i].via.str;
        // cout << "INDIV MSGPACK " << endl << indiv_msgpack.ptr << endl;
        pk.pack(db_put(indiv_msgpack, user_id, need_auth));
    }
}

void
handle_get_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk)
{
    bool need_auth;
    msgpack::unpacker unpk; 
    msgpack::object glob_obj;
    msgpack::object_array obj_arr; 
    msgpack::object_handle result;
    msgpack::object_str user_id;

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

    pk.pack_array((obj_arr.size - 2) * 2 + 1);
    need_auth = obj_arr.ptr[0].via.boolean;    
    user_id = obj_arr.ptr[1].via.str;
    if (need_auth)
        cout << "USER ID " << user_id.ptr << endl;

    printf("NEED AUTH %d\n", need_auth);
    pk.pack(OK);    
    for (int i = 2; i < obj_arr.size; i++) {
        int auth_result = 0;
        char res_buf[MAX_BUF_SIZE];
        size_t res_size;

        msgpack::object_str res_uri;
        res_uri = obj_arr.ptr[i].via.str;
        printf("RES URI %s\n", res_uri.ptr);
        res_size = get_if_exists(res_uri, res_buf);
        if (res_size > 0) {
            cout << "EXISTS" << endl;
            if (need_auth) 
                auth_result = db_auth(user_id.ptr, user_id.size, res_uri.ptr, res_uri.size);
            cout << "AUTH " << auth_result << endl;
            if ((auth_result & ACCESS_CAN_READ) || !need_auth) {
                pk.pack(OK);
                pk.pack_str(res_size);
                pk.pack_str_body(res_buf, res_size);
            } else {
                pk.pack(AUTH_FAILED);
                pk.pack_nil();
            }
        } else  {
            pk.pack(NOT_FOUND);
            pk.pack_nil();
        }
    }
}

int
db_handle_request(lua_State *L)
{
    uint8_t op;
    size_t msg_size;
    const  char *msg;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);

        
    op = lua_tointeger(L, -2);
    msg = lua_tolstring(L, -1, &msg_size);
    printf("@HANDLE REQUEST\n");
    printf("@SIZE %zu\n", msg_size);
    // printf("@MSG %s\n", msg);

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

    if ((acl_space_id = box_space_id_by_name("acl",  
        strlen("acl"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: individuals" << endl;
		return 0;
	}

    if ((acl_index_id = box_index_id_by_name(individuals_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH INDEX: primary" << endl;   
        return 0;
    }

    if ((rdf_types_space_id = box_space_id_by_name("rdf_types",  
        strlen("rdf_types"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: rdf_types" << endl;
		return 0;
	}

    if ((rdf_types_index_id = box_index_id_by_name(rdf_types_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH INDEX: primary" << endl;   
        return 0;
    }
    
    cout << "START MSG " << msg << endl;
    switch (op) {
        case GET: {
            printf("GET=%d %s\n", op, msg);
            handle_get_request(msg, msg_size, pk);
            lua_pushlstring(L, buffer.data(), buffer.size());
            break;
        }
        case PUT: {
            printf("PUT=%d %s\n", op, msg);
            handle_put_request(msg, msg_size, pk);
            printf("PUT RESP szie=%zu %s\n", buffer.size(), buffer.data());
            lua_pushlstring(L, buffer.data(), buffer.size());
            break;
        }
    }

    return 1;
}

int 
luaopen_db_handler(lua_State *L)
{
    lua_register(L, "db_handle_request", db_handle_request);  
	return 0;
} 