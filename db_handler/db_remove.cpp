#include <errno.h>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_globals.h"

#include "individual.h"
#include "right.h"

void 
remove_right_set(vector<Resource> &resource, string prefix)
{
    for (int i = 0; i < resource.size(); i++) {
        string key;
        msgpack::sbuffer buffer;
        msgpack::packer<msgpack::sbuffer> pk(&buffer);

        key = prefix + resource[i].str_data;
        
        pk.pack_array(1);
        pk.pack(key);
        box_delete(acl_index_id, acl_space_id, buffer.data(), buffer.data() 
            + buffer.size(), NULL);
        box_delete(cache_space_id, cache_index_id, buffer.data(), buffer.data() 
            + buffer.size(), NULL);
    }
}

int
db_remove(msgpack::object_str &key, msgpack::object_str &user_id, bool need_auth)
{
    return OK;

    box_tuple_t *tuple;
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);
    map< string, vector<Resource> >::iterator it;
    char *buf;
    int auth_result;
    size_t tuple_size;
    Individual *individual;

    pk.pack_array(1);
    pk.pack_str(key.size);
    pk.pack_str_body(key.ptr, key.size);

    box_index_get(individuals_space_id, individuals_index_id, buffer.data(), buffer.data() 
        + buffer.size(), &tuple);

    if (tuple == NULL)
        return NOT_FOUND;

    tuple_size = box_tuple_bsize(tuple);
    buf = new char[tuple_size];
    box_tuple_to_buf(tuple, buf, tuple_size);

    individual = new Individual();
    if (msgpack_to_individual(individual, buf, tuple_size) < 0) {
        cerr << "@ERR REST! ERR ON DECODING MSGPACK" << endl;
        delete individual;
        delete buf;        
        return BAD_REQUEST;
    }
    delete buf;

    auth_result = db_auth(user_id.ptr, user_id.size, key.ptr, key.size);
    if (!(auth_result & ACCESS_CAN_DELETE) && need_auth) {
        delete individual;
        return AUTH_FAILED;
    }

    box_delete(rdf_types_space_id, rdf_types_index_id, buffer.data(), buffer.data() 
        + buffer.size(), NULL);

    it = individual->resources.find("rdf:type");
    if (it != individual->resources.end()) {
        if (it->second[0].str_data == "v-s:PermissionStatement") 
            remove_right_set(individual->resources["v-s:permissionObject"], PERMISSION_PREFIX);
        else if (it->second[0].str_data == "v-s:Membership")
            remove_right_set(individual->resources["v-s:resource"], MEMBERSHIP_PREFIX);
    }
    box_delete(individuals_space_id, individuals_index_id, buffer.data(), buffer.data() 
        + buffer.size(), NULL);

    delete individual;
    cout << "DELETE OK" << endl;
    return OK;
}