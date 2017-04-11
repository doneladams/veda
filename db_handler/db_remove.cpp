#include <errno.h>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_globals.h"

#include "individual.h"
#include "right.h"

void 
remove_right_set(msgpack::object_str &key, string prefix)
{
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);

    // fprintf(stderr, "DELETE RIGHTS %s\n", key.c_str());
    
    pk.pack_array(1);
    pk.pack(prefix + string(key.ptr, key.size));
    fprintf(stderr, "REMOVE RIGHTSET %s\n", (prefix + string(key.ptr, key.size)).c_str());
    fprintf(stderr, "DELETE RESULT %d\n", box_delete(acl_space_id, acl_index_id, buffer.data(), buffer.data() 
        + buffer.size(), NULL));
    // fprintf(stderr, "ERROR %d %s\n", box_error_code(box_error_last()), box_error_message(box_error_last()));        
}

int
db_remove(msgpack::object_str &key, msgpack::object_str &user_id, bool need_auth)
{
    msgpack::sbuffer buffer;
    msgpack::packer<msgpack::sbuffer> pk(&buffer);
    int auth_result;

    pk.pack_array(1);
    pk.pack_str(key.size);
    pk.pack_str_body(key.ptr, key.size);

    if (box_index_count(individuals_space_id, individuals_index_id, ITER_EQ, buffer.data(), 
        buffer.data() + buffer.size()) == 0)
        return NOT_FOUND;
    
    if (need_auth) {
        auth_result = db_auth(user_id.ptr, user_id.size, key.ptr, key.size);
        if (auth_result < 0)
            return INTERNAL_SERVER_ERROR;
        else if (!(auth_result & ACCESS_CAN_DELETE))
            return AUTH_FAILED;
    }

    remove_right_set(key, PERMISSION_PREFIX);
    remove_right_set(key, MEMBERSHIP_PREFIX);
    box_delete(rdf_types_space_id, rdf_types_index_id, buffer.data(), buffer.data() 
        + buffer.size(), NULL);
    box_delete(individuals_space_id, individuals_index_id, buffer.data(), buffer.data() 
        + buffer.size(), NULL);

    cout << "DELETE OK" << endl;
    return OK;
}