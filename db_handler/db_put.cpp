#include <errno.h>
#include <nanomsg/nn.h>
#include <nanomsg/pair.h>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_globals.h"

#include "individual.h"
#include "right.h"


vector<Resource>
get_delta(vector<Resource> &a, vector<Resource> &b)
{
    vector<Resource> delta;
    // cout << "DEFAULT DELTA SIZE " << delta.size() << endl;
    
    for (int i = 0; i < a.size(); i++) {
        int j;
        for (j = 0; j < b.size(); j++)
            if (a[i] == b[j])
                break;

        if (j < b.size())
            delta.push_back(a[i]);
    }

    // cout << "RESULT DELTA SIZE " << delta.size() << endl;
    return delta;
}

void
peek_from_tarantool(string key, map<string, Right> &new_right_set) 
{
    box_tuple_t *tuple;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);
    msgpack::unpacker unpk;
    size_t tuple_size;
    uint32_t nmb_rights;
    string right_uri;
    char *buf;  


    pk.pack_array(1);
    pk.pack(key);

    box_index_get(acl_space_id, acl_index_id, buffer.data(), buffer.data() + buffer.size(), 
        &tuple);

    if (tuple == NULL)
        return;

    tuple_size = box_tuple_bsize(tuple);
    buf = new char[tuple_size];
    box_tuple_to_buf(tuple, buf, tuple_size);
    
    unpk.reserve_buffer(tuple_size);
    memcpy(unpk.buffer(), buf, tuple_size);
    unpk.buffer_consumed(tuple_size);
    msgpack::object_handle result;
    unpk.next(result);
    msgpack::object right_entry(result.get()); 
    msgpack::object_array right_obj_arr = right_entry.via.array;

    delete buf;

    nmb_rights = right_obj_arr.size;
    right_uri = string(right_obj_arr.ptr->via.str.ptr, right_obj_arr.ptr->via.str.size);

    for (int i = 1; i < right_obj_arr.size; i++) {
        Right right;
        msgpack::object obj;

        obj = right_obj_arr.ptr[i];
        right.id = string(obj.via.str.ptr, obj.via.str.size - 1);
        right.access = obj.via.str.ptr[obj.via.str.size - 1];
        
        // cout << "RIGHT ID " << right.id << " ACCESS " << right.access << endl;
        new_right_set[right.id] = right;
    } 
}

void 
push_into_tarantool(string in_key, map<string, Right> new_right_set)
{
    int count = 0;
    map<string, Right>::iterator it;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);

    pk.pack_array(new_right_set.size() + 1);
    pk.pack(in_key);

    for (it = new_right_set.begin(); it != new_right_set.end(); it++) 
        if (!it->second.is_deleted) { 
            pk.pack(it->second.id + (char)it->second.access);
            count++;
        }

    if (count > 0) {
        if (box_replace(acl_space_id, buffer.data(), buffer.data() + buffer.size(), NULL) < 0)
            cerr << "LISTENER: Error on inserting acl msgpack " << buffer.data() << endl;
    } else if (box_delete(acl_space_id, acl_index_id, buffer.data(), 
        buffer.data() + buffer.size(), NULL) < 0)
            cerr << "LISTENER: Error on deleting acl msgpack " << buffer.data() << endl;
            
}


void update_right_set(vector<Resource> &resource, vector<Resource> &in_set, bool is_deleted, 
    string prefix, uint8_t access)
{

    // cout << "UPDATE" << endl;
    for (int i = 0; i < resource.size(); i++) {
        map<string, Right> new_right_set;
        string key;
        // cout << "\tRES URI " << prefix + resource[i].str_data << endl;

        key = prefix + resource[i].str_data;
        peek_from_tarantool(key, new_right_set);
        for (int j = 0; j < in_set.size(); j++) {
            map<string, Right>::iterator it;
            string in_set_key;

            in_set_key = in_set[j].str_data;
            it = new_right_set.find(in_set_key);
            if (it != new_right_set.end()) {
                it->second.is_deleted = is_deleted;
                it->second.access |= access;
            } else {
                Right right;
                right.id = in_set_key;
                right.access = access;
                right.is_deleted = is_deleted;
                new_right_set[in_set_key] = right;
            }
            
            push_into_tarantool(key, new_right_set);
        }
    }
}

void
prepare_right_set(Individual *prev_state, Individual *new_state, string p_resource, 
    string p_in_set, string prefix)
{
    bool is_deleted = false;
	uint8_t access = 0;
	vector <Resource> new_resource, new_in_set, prev_resource, prev_in_set, delta;
    map< string, vector<Resource> >::iterator it; 

    it = new_state->resources.find("v-d:deleted");
    if (it != new_state->resources.end()) {
        it->second = it->second;
        is_deleted = it->second[0].bool_data;
    }

    it = new_state->resources.find("v-s:canCreate");
    if (it != new_state->resources.end()) {
    	it->second = it->second;
		if (it->second[0].bool_data)
			access |= ACCESS_CAN_CREATE;
    }

	it = new_state->resources.find("v-s:canRead");
    if (it != new_state->resources.end()) {
    	it->second = it->second;
		if (it->second[0].bool_data)
			access |= ACCESS_CAN_READ;
    }

	it = new_state->resources.find("v-s:canUpdate");
    if (it != new_state->resources.end()) {
    	it->second = it->second;
		if (it->second[0].bool_data)
			access |= ACCESS_CAN_UPDATE;
    }

	it = new_state->resources.find("v-s:canDelete");
    if (it != new_state->resources.end()) {
    	it->second = it->second;
		if (it->second[0].bool_data)
			access |= ACCESS_CAN_DELETE;
    }

	access = (access > 0) ? access : DEFAULT_ACCESS;

	new_resource = new_state->resources[p_resource];
	new_in_set = new_state->resources[p_in_set]; 

    // cout << "ACCESS " << (int)access << " " << p_resource << endl;
    delta = get_delta(prev_resource, new_resource);

    update_right_set(new_resource, new_in_set, is_deleted, prefix, access);    
    if (delta.size() > 0) 
        update_right_set(delta, new_in_set, true, prefix, access);
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
get_rdf_types(string &key, vector<string> &rdf_types)
{
    box_tuple_t *tuple;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);
    msgpack::object_handle result;    
    msgpack::unpacker unpk;
    msgpack::object glob_obj;
    msgpack::object_array obj_arr;
    size_t tuple_size;
    char *buf;  


    pk.pack_array(1);
    pk.pack(key);

    box_index_get(acl_space_id, acl_index_id, buffer.data(), buffer.data() + buffer.size(), 
        &tuple);

    if (tuple == NULL)
        return 0;

    tuple_size = box_tuple_bsize(tuple);
    buf = new char[tuple_size];
    box_tuple_to_buf(tuple, buf, tuple_size);

    unpk.reserve_buffer(tuple_size);
    memcpy(unpk.buffer(), buf, tuple_size);
    unpk.buffer_consumed(tuple_size);
    unpk.next(result);
    glob_obj = msgpack::object(result.get()); 
    obj_arr = glob_obj.via.array;

    delete buf;

    if (obj_arr.size < 2)
        return -1;

    for (int i = 1; i < obj_arr.size; i++) 
       rdf_types.push_back(string(obj_arr.ptr[i].via.str.ptr, obj_arr.ptr[i].via.str.size));
    
    return rdf_types.size();
}

int
db_put(msgpack::object_str &indiv_msgpack, msgpack::object_str &user_id, bool need_auth)
{
    Individual *individual;
    Individual *prev_state, *new_state;
    map< string, vector<Resource> >::iterator it;
    vector<Resource> tmp_vec, rdf_type;
    bool is_update = true;
    int auth_result;
    
    individual = new Individual();
    if (msgpack_to_individual(individual, indiv_msgpack.ptr, indiv_msgpack.size) < 0) {
        cerr << "@ERR REST! ERR ON ENCODING MSGPACK";
        return BAD_REQUEST;
    }
    
    new_state = new Individual();
    it = individual->resources.find("new_state");
    if(it != individual->resources.end()) {
        const char *tmp_ptr;
        uint32_t tmp_len;

        it = new_state->resources.find("rdf:type");
        if (it == individual->resources.end()) {
            cerr << "@ERR REST! NO RDF TYPE FOUND!";
            return BAD_REQUEST;
        }
        rdf_type = it->second;

        if (need_auth) {   
            int res;
            vector<string> tnt_rdf_types;

            res = get_rdf_types(individual->uri, tnt_rdf_types);
            if (res < 0) {
                cerr << "@ERR REST! GET RDF TYPES ERR!" << endl;
                return INTERNAL_SERVER_ERROR;
            } else if (res > 0) {
                vector<string>::iterator it;
                for (int i = 0; i < rdf_type.size(); i++) {
                    it = find(tnt_rdf_types.begin(), tnt_rdf_types.end(), rdf_type[i].str_data);
                    if (it == tnt_rdf_types.end()) {
                        is_update = false;
                        auth_result = db_auth(user_id.ptr, user_id.size, rdf_type[i].str_data.c_str(), 
                            rdf_type[i].str_data.size());
                        if (!(auth_result & ACCESS_CAN_CREATE))
                            return AUTH_FAILED;
                    }
                }
            }
                
        }

        if (is_update) {
            auth_result = db_auth(user_id.ptr, user_id.size, individual->uri.c_str(),
                individual->uri.size());
            if (!(auth_result & ACCESS_CAN_UPDATE))
                return AUTH_FAILED;
        }
            
        tmp_vec  = it->second;
        // cout << "NEW STATE " << tmp_vec[0].str_data << endl;
        tmp_ptr = tmp_vec[0].str_data.c_str();
        tmp_len = tmp_vec[0].str_data.length();
        if (box_replace(individuals_space_id, tmp_ptr, tmp_ptr + tmp_len, NULL) < 0) {
            delete new_state;
            cerr << "@ERR REST: ERR ON INSERTING MSGPACK" << endl;
            return INTERNAL_SERVER_ERROR;
        }

        if (msgpack_to_individual(new_state, tmp_ptr, tmp_len) < 0) {
            delete new_state;            
            cerr << "@ERR REST! ERR ON DECODING NEW_STATE" << endl << endl;
            return INTERNAL_SERVER_ERROR;
        }
    } else {
        delete new_state;
        cerr << "@ERR REST! NO NEW STATE" << endl;
        return BAD_REQUEST;
    }

    it = individual->resources.find("prev_state");
    prev_state = new Individual();
    if(it != individual->resources.end()) {
        const char *tmp_ptr;
        uint32_t tmp_len;

        tmp_vec  = it->second;
        tmp_ptr = tmp_vec[0].str_data.c_str();
        tmp_len = tmp_vec[0].str_data.length();
        if (msgpack_to_individual(prev_state, tmp_ptr, tmp_len) < 0) {
            delete prev_state;
            delete new_state;
            cerr << "@ERR REST! ERR ON DECODING PREV_STATE" << endl;
            return BAD_REQUEST;
        }
    }
    
    it = new_state->resources.find("rdf:type");
    if (it != new_state->resources.end()) {
        if (it->second[0].str_data == "v-s:PermissionStatement") 
            prepare_right_set(prev_state, new_state, "v-s:permissionObject", 
                "v-s:permissionSubject", PERMISSION_PREFIX);
        else if (it->second[0].str_data == "v-s:Membership")
            prepare_right_set(prev_state, new_state, "v-s:resource", "v-s:memberOf", 
                MEMBERSHIP_PREFIX);
    }
    
    return OK;
}
