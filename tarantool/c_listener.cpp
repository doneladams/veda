#include <arpa/inet.h>
#include <errno.h>
#include <strings.h>
#include <signal.h>
#include <nanomsg/nn.h>
#include <nanomsg/pair.h>
#include <tarantool/module.h>
#include <unistd.h>
#include <sys/time.h>

#include "individual.h"

extern "C" {
	int c_listener_start(lua_State *L);	
	int luaopen_c_listener(lua_State *L);
}

int 
msgpack_to_individual(Individual *individual, const char *msgpack)
{
	uint32_t msg_len, uri_len, map_len;
	const char *uri_ptr;
    msg_len = mp_decode_array(&msgpack);

    if (msg_len != 2) {
        cerr << "@LISTENER ERROR! INVALID MSGPACK;" << endl;
		return -1;
	}
    
    uri_ptr = mp_decode_str(&msgpack, &uri_len);

    
    individual->uri = string(uri_ptr, uri_len);
    
	map_len = mp_decode_map(&msgpack);
    
    for (int i = 0; i < map_len; i++ ) {
		const char *predicate_ptr;
		uint32_t predicate_len, resources_len;
        vector <Resource> resources;

		if (mp_typeof(*msgpack) != MP_STR) {
			std::cerr << "@ERR LISTENER! PREDICATE IS NOT STRING!" << endl;
            return -1;
		}
		
		predicate_ptr = mp_decode_str(&msgpack, &predicate_len);
        string predicate(predicate_ptr, predicate_len);
        resources_len = mp_decode_array(&msgpack);

        // std::cerr << "SIZE " << res_objs.size << endl;
        for (int j = 0; j < resources_len; j++) {
                        
            switch (mp_typeof(*msgpack)) {
                case MP_ARRAY: {
					uint32_t res_arr_len;
					uint64_t type;
                    
					res_arr_len = mp_decode_array(&msgpack);
                    if (res_arr_len == 2) {
						type = mp_decode_uint(&msgpack);

                        if (type == _Datetime) {
                            Resource rr;

                            rr.type      = _Datetime;
							if (mp_typeof(*msgpack) == MP_INT)
								rr.long_data = mp_decode_int(&msgpack);
                            else
                                rr.long_data = mp_decode_uint(&msgpack);
                                
                            resources.push_back(rr);
                        } else if (type == _String) {
                            Resource    rr;

                            rr.type = _String;
                            
                            if (mp_typeof(*msgpack) == MP_STR) {
								const char *str_data_ptr;
								uint32_t str_data_len;

								str_data_ptr = mp_decode_str(&msgpack, &str_data_len);
                                rr.str_data = string(str_data_ptr, str_data_len);
							} else if (mp_typeof(*msgpack) == MP_NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR LISTENER! NOT A STRING" 
									" IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }

                            rr.lang = LANG_NONE;
                            resources.push_back(rr);
                        }
                        else {
                            std::cerr << "@ERR LISTENER! UNKNOWN TYPE IN" 
								" RESORCE ARRAY 2!" << endl;
                            return -1;
                        }
                    }
                    else if (res_arr_len == 3) {
                        type = mp_decode_uint(&msgpack);
                        if (type == _Decimal) {
                            long mantissa, exponent;
                            Resource rr;

							if (mp_typeof(*msgpack) == MP_INT)
								mantissa = mp_decode_int(&msgpack);
                            else
                                mantissa = mp_decode_uint(&msgpack);

							if (mp_typeof(*msgpack) == MP_INT)
								exponent = mp_decode_int(&msgpack);
                            else
                                exponent = mp_decode_uint(&msgpack);


                            rr.type                  = _Decimal;
                            rr.decimal_mantissa_data = mantissa;
                            rr.decimal_exponent_data = exponent;
                            resources.push_back(rr);
                        } else if (type == _String) {
                            Resource    rr;
                            
                            rr.type = _String;
                            if (mp_typeof(*msgpack) == MP_STR) {
								const char *str_data_ptr;
								uint32_t str_data_len;

								str_data_ptr = mp_decode_str(&msgpack, &str_data_len);
                                rr.str_data = string(str_data_ptr, str_data_len);
							} else if (mp_typeof(*msgpack) == MP_NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR LISTENER! NOT A STRING" 
									"IN RESOURCE ARRAY 3" << endl;
                                return -1;
                            }
                
							rr.lang     = mp_decode_uint(&msgpack);
                            resources.push_back(rr);

                        }
                        else
                        {
                            std::cerr << "@ERR LISTENER! UNKNOWN TYPE IN" 
								" RESORCE ARRAY 3!" << endl;
                            return -1;
                        }
                    } else {
                        std::cerr << "@ERR LISTENER! UNKNOWN ARRAY SIZE!" << endl;
                        return -1;
                    }
                    break;
                }

                case MP_STR: {
					const char *str_data_ptr;
					uint32_t str_data_len;


                    Resource    rr;
                    rr.type = _Uri;
                    str_data_ptr = mp_decode_str(&msgpack, &str_data_len);
                    rr.str_data = string(str_data_ptr, str_data_len);
                    resources.push_back(rr);
                    break;
                }

                case MP_UINT: {
                    Resource rr;
                    rr.type      = _Integer;
					rr.long_data = mp_decode_uint(&msgpack);
                    resources.push_back(rr);
                    break;
                }

                case MP_INT:
                {
                    Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = mp_decode_int(&msgpack);;
                    resources.push_back(rr);
                    break;
                }       

                case MP_BOOL: {
                    Resource rr;
                    rr.type      = _Boolean;
					rr.bool_data = mp_decode_bool(&msgpack);
                    resources.push_back(rr);
                    break;
                } 

                default: {
                    std::cerr << "@ERR LISTENER! UNSUPPORTED"
						" RESOURCE TYPE " << mp_typeof(*msgpack) << endl;
                }  
            }
        }

        // std::cerr << "RES SIZE " << resources.size() << endl;
        individual->resources[predicate] = resources;        
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

/*		map< string, vector<Resource> >::iterator it = m.find('2');
Bar b3;
if(it != m.end())
{
   //element found;
   b3 = it->second;
}*/

		
		msgpack = NULL;
		size = nn_recv(socket_fd, &msgpack, NN_MSG, 0);
		
		individual = new Individual();
		if (msgpack_to_individual(individual, msgpack) < 0) {
			cerr << "@ERR LISTENER! ERR ON DECODING MSGPACK" << endl << msgpack << endl;
			nn_freemsg(msgpack);
			continue;
		}		

		new_state = new Individual();
		it = individual->resources.find("new_state");
		if(it != individual->resources.end()) {
			tmp_vec  = it->second;
			if (msgpack_to_individual(new_state, tmp_vec[0].str_data.c_str()) < 0) {
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

		it = individual->resources.find("old_state");
		if(it != individual->resources.end()) {
			tmp_vec  = it->second;
			if (msgpack_to_individual(new_state, tmp_vec[0].str_data.c_str()) < 0) {
				cerr << "@ERR LISTENER! ERR ON DECODING NEW_STATE" << endl << msgpack << endl;
				nn_freemsg(msgpack);
				continue;
			}
		}
		
		
		if (box_replace(individuals_space_id, msgpack, msgpack + size, NULL) < 0) {
			fprintf(stderr, "LISTENER: Error on inserting msgpack %s\n", msgpack);
			nn_close(socket_fd);
			return 0;
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