#include <errno.h>
#include <tarantool/module.h>

#include "db_auth.h"
#include "db_codes.h"
#include "db_globals.h"

#include "individual.h"
#include "right.h"

size_t
db_get(msgpack::object_str &key, char *out_buf)
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