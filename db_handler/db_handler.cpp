#include <errno.h>
#include <iostream>
#include <msgpack.hpp>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_remove.h"
#include "db_get.h"
#include "db_put.h"

using namespace std;

#define PUT         1
#define GET         2
#define AUTHORIZE   8
#define REMOVE      51

#define ACCESS_CAN_CREATE 	(1U << 0)
#define ACCESS_CAN_READ 	(1U << 1)
#define ACCESS_CAN_UPDATE 	(1U << 2)
#define ACCESS_CAN_DELETE 	(1U << 3)

// #define MAX_BUF_SIZE 16384


extern "C" {
	int db_handle_request(lua_State *L);	
	int luaopen_db_handler(lua_State *L);
}


uint32_t individuals_space_id, individuals_index_id;
uint32_t rdf_types_space_id, rdf_types_index_id;
uint32_t acl_space_id, acl_index_id, cache_space_id, cache_index_id;

void 
handle_authorize_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk, 
    msgpack::object_array &obj_arr)
{
    msgpack::object_str user_id;

    pk.pack_array((obj_arr.size - 3) * 2 + 1);
    user_id = obj_arr.ptr[2].via.str;

    pk.pack(OK);
    for (uint32_t i = 3; i < obj_arr.size; i++) {
        uint8_t auth_result = 0;
        msgpack::sbuffer buffer;
        msgpack::packer<msgpack::sbuffer> res_pk(&buffer);
        msgpack::object_str res_uri;

        res_uri = obj_arr.ptr[i].via.str;
        res_pk.pack_array(1);
        res_pk.pack_str(res_uri.size);
        res_pk.pack_str_body(res_uri.ptr, res_uri.size);

        fprintf (stderr, "RES URI %.*s\n", (int)res_uri.size, res_uri.ptr);
        if (box_index_count(individuals_space_id, individuals_index_id, ITER_EQ, buffer.data(), 
            buffer.data() + buffer.size()) > 0) {
            auth_result = db_auth(user_id.ptr, user_id.size, res_uri.ptr, res_uri.size);
            fprintf(stderr, "AUTHORIZE RESULT %d\n", auth_result);        
            if (auth_result < 0) {
                pk.pack(INTERNAL_SERVER_ERROR);
                pk.pack(0);
                continue;
            }
            pk.pack(OK);
            // auth_result = 0;
            pk.pack(auth_result);
            // pk.pack(OK);
            // pk.pack(15);
        } else {
            pk.pack(NOT_FOUND);
            pk.pack(0);
        }
    }
}

void handle_put_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk, msgpack::object_array &obj_arr)
{
    bool need_auth;
    msgpack::object_str user_id;

    pk.pack_array(obj_arr.size - 3 + 1);
    need_auth = obj_arr.ptr[1].via.boolean;
    user_id = obj_arr.ptr[2].via.str;

    fprintf (stderr, "NEED AUTH %d [%*.s]\n", need_auth, (int)user_id.size, user_id.ptr);
    pk.pack(OK);
    for (uint32_t i = 3; i < obj_arr.size; i++) {
        int put_result;
        msgpack::object_str indiv_msgpack;
        // fprintf (stderr, "size=%u i=%u\n", obj_arr.size, i);
        
        indiv_msgpack = obj_arr.ptr[i].via.str;
        // cout << "INDIV MSGPACK " << endl << indiv_msgpack.ptr << endl;
        put_result = db_put(indiv_msgpack, user_id, need_auth);
        fprintf(stderr, "PUT RESULT %d\n", put_result);
        pk.pack(put_result);
    }
}

void handle_remove_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk, msgpack::object_array &obj_arr)
{
    bool need_auth;
    msgpack::object_str user_id;

//    fprintf (stderr, "REMOVE:obj_arr.size=%d\n", obj_arr.size);

    pk.pack_array(obj_arr.size - 3 + 1);
    need_auth = obj_arr.ptr[1].via.boolean;
    user_id = obj_arr.ptr[2].via.str;
    // fprintf (stderr, "REMOVE:user_id.length=%d\n", (int)user_id.size);
    //fprintf (stderr, "REMOVE:USER URI(%d) [%*.s]\n", (int)user_id.size, (int)user_id.size, user_id.ptr);
    //cout << "MSG " << msg << endl;
    //if (need_auth)
    //    cout << "USER ID " << user_id.ptr << endl;

    //fprintf (stderr, "NEED AUTH %d\n", need_auth);
    pk.pack(OK);
    for (uint32_t i = 3; i < obj_arr.size; i++) {
        int remove_result = 0;
        msgpack::object_str res_uri;
        // fprintf (stderr, "size=%u i=%u\n", obj_arr.size, i);
        res_uri = obj_arr.ptr[i].via.str;
//        fprintf (stderr, "REMOVE:DELETE RES URI [%*.s]\n", (int)res_uri.size, res_uri.ptr);
        // cout << "INDIV MSGPACK " << endl << indiv_msgpack.ptr << endl;
        fprintf(stderr, "TRY REMOVE %.*s\n", (int)res_uri.size, res_uri.ptr);
        remove_result = db_remove(res_uri, user_id, need_auth);
        fprintf(stderr, "REMOVE RESULT %d\n", remove_result);
//        fprintf (stderr, "REMOVE #1\n");
        pk.pack(remove_result);
        // fprintf (stderr, "REMOVE #E\n");
    }
}

void
handle_get_request(const char *msg, size_t msg_size, msgpack::packer<msgpack::sbuffer> &pk, 
    msgpack::object_array &obj_arr)
{
    bool need_auth;
    msgpack::object_str user_id;
    // char res_buf[MAX_BUF_SIZE];
    char *res_buf;
    
    
    pk.pack_array((obj_arr.size - 3) * 2 + 1);
    need_auth = obj_arr.ptr[1].via.boolean;    
    user_id = obj_arr.ptr[2].via.str;
    
    //fprintf (stderr, "NEED AUTH %d\n", need_auth);
    pk.pack(OK);    
    for (int i = 3; i < obj_arr.size; i++) {
        int auth_result = 0;
        size_t res_size;

        msgpack::object_str res_uri;
        res_uri = obj_arr.ptr[i].via.str;
        fprintf (stderr, "RES URI %.*s need_auth=%d\n", (int)res_uri.size, res_uri.ptr, (int)need_auth);
        res_size = db_get(res_uri, &res_buf);
        if (res_size > 0) {
            //cerr << "EXISTS" << endl;
            if (need_auth) { 
                auth_result = db_auth(user_id.ptr, user_id.size, res_uri.ptr, res_uri.size);
                if (auth_result < 0) {
                    pk.pack(INTERNAL_SERVER_ERROR);
                    pk.pack_nil();
                    continue;
                }
            }
            //cerr << "AUTH " << auth_result << endl;
            if ((auth_result & ACCESS_CAN_READ) || !need_auth) {
                pk.pack(OK);
                //cerr << "TRY PACK SIZE" << endl;
                pk.pack_str(res_size);
                //cerr << "TRY PACK BODY" << endl;
                pk.pack_str_body(res_buf, res_size);
                //cout << "PACKED" << endl;
                fprintf(stderr, "GET OK\n");
                delete res_buf;
            } else {
                pk.pack(AUTH_FAILED);
                pk.pack_nil();
                fprintf(stderr, "GET AUTH FAILED\n");
    		    //fprintf (stderr, "GET AUTH FAILED, URI=[%.*s]\n", (int)res_uri.size, res_uri.ptr);
                //fprintf (stderr, "\tUSER URI=[%.*s] AUTH RESULT=%d\n", (int)user_id.size, user_id.ptr, 
                //    auth_result);
            }
        } else  {
            fprintf(stderr, "GET NOT FOUND\n");     
            pk.pack(NOT_FOUND);
            pk.pack_nil();
	        //fprintf (stderr, "GET NOT FOUND, URI=[%.*s]\n", (int)res_uri.size, res_uri.ptr);
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
    msgpack::unpacker unpk; 
    msgpack::object glob_obj;
    msgpack::object_array obj_arr; 
    msgpack::object_handle result;

        
    
    msg = lua_tolstring(L, -1, &msg_size);
    // fprintf (stderr, "@HANDLE REQUEST\n");
    //fprintf (stderr, "@SIZE %zu\n", msg_size);
    // fprintf (stderr, "@MSG %s\n", msg);

	if ((individuals_space_id = box_space_id_by_name("individuals",  
        strlen("individuals"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: individuals" << endl;
		return 0;
	}

    if ((individuals_index_id = box_index_id_by_name(individuals_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {    
        cerr << "@ERR LISTENER! NO SUCH INDIVIDUAL INDEX: primary" << endl;   
        return 0;
    }

    if ((acl_space_id = box_space_id_by_name("acl", strlen("acl"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: individuals" << endl;
		return 0;
	}

    if ((acl_index_id = box_index_id_by_name(acl_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH ACL INDEX: primary" << endl;   
        return 0;
    }

   /* if ((cache_space_id = box_space_id_by_name("acl_cache",  
        strlen("acl"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: acl_cache" << endl;
		return 0;
	}

    if ((cache_index_id = box_index_id_by_name(cache_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH ACL INDEX: primary" << endl;   
        return 0;
    }*/

    if ((rdf_types_space_id = box_space_id_by_name("rdf_types",  
        strlen("rdf_types"))) == BOX_ID_NIL) {
		cerr << "@ERR LISTENER! NO SUCH SPACE: rdf_types" << endl;
		return 0;
	}

    if ((rdf_types_index_id = box_index_id_by_name(rdf_types_space_id, "primary", 
        strlen("primary"))) == BOX_ID_NIL) {
        cerr << "@ERR LISTENER! NO SUCH RDF_TYPES INDEX: primary" << endl;   
        return 0;
    }
    
    // cout << "START MSG " << msg << endl;
    unpk.reserve_buffer(msg_size);
    memcpy(unpk.buffer(), msg, msg_size);
    unpk.buffer_consumed(msg_size);
    unpk.next(result);
    glob_obj = msgpack::object(result.get()); 
    obj_arr = glob_obj.via.array;
    
    if (obj_arr.size < 4) {
        cerr << "@ERR! MSGPACK ARR SIZE SMALLER THEN 4!" << endl;
        pk.pack_array(1);
        pk.pack(BAD_REQUEST);
        lua_pushlstring(L, buffer.data(), buffer.size());
        return 1;
    }

    if (obj_arr.ptr[2].type == msgpack::type::NIL) {
        cerr << "@ERR! NIL USER ID!" << endl;
        pk.pack_array(1);
        pk.pack(INTERNAL_SERVER_ERROR);
        lua_pushlstring(L, buffer.data(), buffer.size());
        return 1;
    }

    op = (uint8_t)obj_arr.ptr[0].via.u64;
    //cout << "OP " << (int)op << endl;
    switch (op) {
        case GET: {
            //fprintf (stderr, "GET=%d %s\n", op, msg);
	        fprintf (stderr, "-------- GET ----------\n");
            handle_get_request(msg, msg_size, pk, obj_arr);
	        fprintf (stderr, "--------\n");
//            fprintf (stderr, "GET RESP szie=%zu %.*s\n", buffer.size(), (int)buffer.size(), buffer.data());
            break;
        }
        case PUT: {
            fprintf (stderr, "-------- PUT ----------\n");
            //fprintf (stderr, "PUT=%d %s\n", op, msg);
            handle_put_request(msg, msg_size, pk, obj_arr);
            fprintf (stderr, "--------\n");
//            fprintf (stderr, "PUT RESP szie=%zu %.*s\n", buffer.size(), (int)buffer.size(), buffer.data());
            break;
        }
        case REMOVE: {
            fprintf (stderr, "-------- REMOVE ----------\n");
            handle_remove_request(msg, msg_size, pk, obj_arr);
            fprintf (stderr, "--------\n");
//            fprintf (stderr, "REMOVE RESP szie=%zu %.*s\n", buffer.size(), (int)buffer.size(), buffer.data());
            break;
        }
        case AUTHORIZE: {
            fprintf (stderr, "-------- AUTHORIZE ----------\n");            
            handle_authorize_request(msg, msg_size, pk, obj_arr);
            fprintf (stderr, "--------\n");
	        break;
        }

        default: {
            fprintf (stderr, "@ERR! [%d] UNKNOWN REQUEST!\n", op);
            pk.pack_array(1);
            pk.pack(BAD_REQUEST);
        }
    }
    
    // fprintf(stderr, "PUSH ANSWER BACK\n");
    lua_pushlstring(L, buffer.data(), buffer.size());    
    // fprintf(stderr, "RETURNING\n");    
    return 1;
}

int 
luaopen_db_handler(lua_State *L)
{
    lua_register(L, "db_handle_request", db_handle_request);  
	return 0;
} 