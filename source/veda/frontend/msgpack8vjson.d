/**
 * msgpack -> vibe.d json

   Copyright: © 2014-2017 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */

module veda.frontend.msgpack8vjson;

private import std.outbuffer, std.stdio, std.string, std.conv, std.datetime;
private import vibe.data.json;
private import veda.common.type, veda.onto.resource, veda.onto.individual, veda.onto.lang, veda.bind.msgpuck;

public int msgpack2vjson(Json *individual, string in_str)
{
    try
    {
        char *ptr         = cast(char *)in_str.ptr;
        int  root_el_size = mp_decode_array(&ptr);

        if (root_el_size != 2)
            return -1;

        uint uri_lenght;
        char *uri = mp_decode_str(&ptr, &uri_lenght);
        (*individual)[ "@" ] = uri[ 0..uri_lenght ].dup;

        int predicates_length = mp_decode_map(&ptr);

        foreach (idx; 0..predicates_length)
        {
            uint   key_lenght;
            char   *key          = mp_decode_str(&ptr, &key_lenght);
            string predicate_uri = key[ 0..key_lenght ].dup;

            Json   resources = Json.emptyArray;

            int    resources_el_length = mp_decode_array(&ptr);
            foreach (i_resource; 0..resources_el_length)
            {
                Json    resource_json = Json.emptyObject;
                mp_type el_type       = mp_typeof(*ptr);

                if (el_type == mp_type.MP_ARRAY)
                {
                    int predicate_el_length = mp_decode_array(&ptr);
                    if (predicate_el_length == 2)
                    {
                        long type = mp_decode_uint(&ptr);

                        if (type == DataType.Datetime)
                        {
                            long value = mp_decode_uint(&ptr);

                            resource_json[ "type" ] = text(DataType.Datetime);
                            SysTime st = SysTime(unixTimeToStdTime(value), UTC());
                            resource_json[ "data" ] = st.toISOExtString();
                        }
                        else if (type == DataType.String)
                        {
                            uint val_length;
                            char *val = mp_decode_str(&ptr, &val_length);
                            resource_json[ "type" ] = text(DataType.String);

                            resource_json[ "data" ] = val[ 0..val_length ].dup;
                            resource_json[ "lang" ] = text(LANG.NONE);
                        }
                        else
                            return -1;
                    }
                    else if (predicate_el_length == 3)
                    {
                        long type = mp_decode_uint(&ptr);

                        if (type == DataType.Decimal)
                        {
                            long mantissa = mp_decode_uint(&ptr);
                            long exponent = mp_decode_uint(&ptr);

                            resource_json[ "type" ] = text(DataType.Decimal);

                            auto dres = decimal(mantissa, cast(byte)exponent);
                            resource_json[ "data" ] = dres.asString();
                        }
                        else if (type == DataType.String)
                        {
                            uint val_length;
                            char *val = mp_decode_str(&ptr, &val_length);
                            long lang = mp_decode_uint(&ptr);

                            resource_json[ "type" ] = text(DataType.String);

                            resource_json[ "data" ] = val[ 0..val_length ].dup;
                            resource_json[ "lang" ] = text(cast(LANG)lang);
                        }
                        else
                            return -1;
                    }
                    else
                    {
                        return -1;
                    }
                }
                else if (el_type == mp_type.MP_STR)
                {
                    // this uri
                    uint val_length;
                    char *val = mp_decode_str(&ptr, &val_length);
                    resource_json[ "type" ] = text(DataType.Uri);
                    resource_json[ "data" ] = val[ 0..val_length ].dup;
                }
                else if (el_type == mp_type.MP_INT)
                {
                    // this int
                    long val = mp_decode_uint(&ptr);
                    resource_json[ "type" ] = text(DataType.Integer);
                    resource_json[ "data" ] = val;
                }
                else if (el_type == mp_type.MP_BOOL)
                {
                    // this bool
                    long val = mp_decode_bool(&ptr);
                    resource_json[ "type" ] = text(DataType.Boolean);
                    resource_json[ "data" ] = val;
                }
                else
                    return -1;

                resources ~= resource_json;
            }
            (*individual)[ predicate_uri ] = resources;
        }

        return -1; //read_element(individual, cast(ubyte[])in_str, dummy);
    }
    catch (Throwable ex)
    {
        writeln("ERR! msgpack2individual ex=", ex.msg, ", in_str=", in_str);
        //printPrettyTrace(stderr);
        //throw new Exception("invalid cbor");
        return -1;
    }
}
