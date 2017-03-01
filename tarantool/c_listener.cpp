#include <errno.h>
#include <nanomsg/nn.h>
#include <nanomsg/pair.h>
#include <tarantool/module.h>

#include "individual.h"

extern "C" {
	int c_listener_start(lua_State *L);	
	int luaopen_c_listener(lua_State *L);
}

int32_t 
msgpack_to_individual(Individual *individual, const char *ptr, uint32_t len)
{
    msgpack::unpacker unpk;    

    unpk.reserve_buffer(len);
    memcpy(unpk.buffer(), ptr, len);
    unpk.buffer_consumed(len);
    msgpack::object_handle result;
    unpk.next(result);
    msgpack::object glob_obj(result.get()); 
    msgpack::object_array obj_arr = glob_obj.via.array;

    if (obj_arr.size != 2)
        return -1;
    
    msgpack::object *obj_uri = obj_arr.ptr;
    msgpack::object *obj_map = obj_arr.ptr + 1;
    
    individual->uri = string(obj_uri->via.str.ptr, obj_uri->via.str.size);
    
    msgpack::object_map map = obj_map->via.map;
    
    for (int i = 0; i < map.size; i++ ) {
        msgpack::object_kv pair = map.ptr[i];
        msgpack::object key = pair.key;
        msgpack::object_array res_objs = pair.val.via.array;
        if (key.type != msgpack::type::STR) {
            std::cerr << "@ERR! PREDICATE IS NOT STRING!" << endl;
            return -1;
        }

        std::string predicate(key.via.str.ptr, key.via.str.size);
        vector <Resource> resources;
        

        for (int j = 0; j < res_objs.size; j++) {
            msgpack::object value = res_objs.ptr[j];
            
            switch (value.type) {
                case msgpack::type::ARRAY: {
                    msgpack::object_array res_arr = value.via.array;
                    if (res_arr.size == 2) {
                        long type = res_arr.ptr[0].via.u64;

                        if (type == _Datetime) {
                            Resource rr;
                            rr.type      = _Datetime;
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER)
                                rr.long_data = res_arr.ptr[1].via.u64;
                            else
                                rr.long_data = res_arr.ptr[1].via.i64;
                                
                            resources.push_back(rr);
                        }
                        else if (type == _String) {
                            Resource    rr;

                            rr.type = _String;
                            
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }

                            rr.lang = LANG_NONE;
                            resources.push_back(rr);
                        }
                        else {
                            std::cerr << "@1" << endl;
                            return -1;
                        }
                    } else if (res_arr.size == 3) {
                        long type = res_arr.ptr[0].via.u64;
                        if (type == _Decimal) {
                            long mantissa, exponent;
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER)
                                mantissa = res_arr.ptr[1].via.u64;
                            else
                                mantissa = res_arr.ptr[1].via.i64;
                            if (res_arr.ptr[2].type == msgpack::type::POSITIVE_INTEGER)
                                exponent = res_arr.ptr[2].via.u64;
                            else
                                exponent = res_arr.ptr[2].via.i64;

                            Resource rr;
                            rr.type                  = _Decimal;
                            rr.decimal_mantissa_data = mantissa;
                            rr.decimal_exponent_data = exponent;
                            resources.push_back(rr);
                        }
                        else if (type == _String) {
                            Resource    rr;
                            
                            rr.type = _String;
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }
                
                            long lang = res_arr.ptr[2].via.u64;
                            rr.lang     = lang;
                            resources.push_back(rr);

                        } else {
                            std::cerr << "@2" << endl;
                            return -1;
                        }
                    }
                    else {
                        std::cerr << "@3" << endl;
                        return -1;
                    }
                    break;
                }

                case msgpack::type::STR: {
                    Resource    rr;
                    rr.type = _Uri;
                    rr.str_data = string(string(value.via.str.ptr, value.via.str.size));
                    resources.push_back(rr);
                    break;
                }

                case msgpack::type::POSITIVE_INTEGER: {
                    Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.u64;
                    resources.push_back(rr);
                    break;
                }

                case msgpack::type::NEGATIVE_INTEGER: {
                    Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.i64;
                    resources.push_back(rr);
                    break;
                }       

                case msgpack::type::BOOLEAN: {
                    Resource rr;
                    rr.type      = _Boolean;
                    rr.bool_data = value.via.boolean;
                    resources.push_back(rr);
                    break;
                } 

                default: {
                    std::cerr << "@ERR! UNSUPPORTED RESOURCE TYPE " << value.type << endl;
                    return -1;  
                }  
            }
        }

        individual->resources[ predicate ] = resources;        
    }

    return 0;
}

int
c_listener_start(lua_State *L)
{
	uint32_t individuals_space_id;
	int socket_fd;

	cout << "@LISTENER STARTED\n" << endl;

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
		return 0;
	}
			
	for (;;	) {
		char *msgpack;
		ssize_t size;
		Individual *individual;
		Individual *prev_state, *new_state;
		map< string, vector<Resource> >::iterator it;
		vector<Resource> tmp_vec;
		
		msgpack = NULL;
		size = nn_recv(socket_fd, &msgpack, NN_MSG, 0);
		
		individual = new Individual();
		if (msgpack_to_individual(individual, msgpack, size) < 0) {
			cerr << "@ERR LISTENER! ERR ON DECODING MSGPACK" << endl << msgpack << endl;
			nn_freemsg(msgpack);
			continue;
		}		

		new_state = new Individual();
		it = individual->resources.find("new_state");
		if(it != individual->resources.end()) {
            const char *tmp_ptr;
            uint32_t tmp_len;
			
            tmp_vec  = it->second;
            // cout << "NEW STATE " << tmp_vec[0].str_data << endl;
            tmp_ptr = tmp_vec[0].str_data.c_str();
            tmp_len = tmp_vec[0].str_data.length();
            if (box_replace(individuals_space_id, tmp_ptr, tmp_ptr + tmp_len, NULL) < 0) {
                fprintf(stderr, "LISTENER: Error on inserting msgpack %s\n", msgpack);
                nn_close(socket_fd);
                return 0;
		    }
			if (msgpack_to_individual(new_state, tmp_ptr, tmp_len) < 0) {
				cerr << "@ERR LISTENER! ERR ON DECODING NEW_STATE" << endl << msgpack << endl;
				nn_freemsg(msgpack);
				continue;
			}
		} else {
			delete new_state;
			cerr << "@ERR LISTENER! NO NEW STATE" << endl;
			nn_freemsg(msgpack);
			continue;
		}

		it = individual->resources.find("prev_state");
        prev_state = NULL;
		if(it != individual->resources.end()) {
            const char *tmp_ptr;
            uint32_t tmp_len;

            prev_state = new Individual();
			tmp_vec  = it->second;
            tmp_ptr = tmp_vec[0].str_data.c_str();
            tmp_len = tmp_vec[0].str_data.length();
			if (msgpack_to_individual(prev_state, tmp_ptr, tmp_len) < 0) {
				cerr << "@ERR LISTENER! ERR ON DECODING PREV_STATE" << endl << msgpack << endl;
				nn_freemsg(msgpack);
				continue;
			}
		}
		
		nn_freemsg(msgpack);
	}
	
	nn_close(socket_fd);			
	return 0;
}



int 
luaopen_c_listener(lua_State *L)
{
	lua_register(L, "c_listener_start", c_listener_start);  
	return 0;
}