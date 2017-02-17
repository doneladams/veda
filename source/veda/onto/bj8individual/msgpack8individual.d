/**
 * msgpack <-> individual

   Copyright: © 2014-2017 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */

module veda.onto.bj8individual.msgpack8individual;

private import std.outbuffer, std.stdio, std.string, std.conv;
private import veda.common.type, veda.onto.resource, veda.onto.individual, veda.onto.lang, veda.bind.msgpuck;
import veda.util.tests_tools;
//import backtrace.backtrace;
//import Backtrace = backtrace.backtrace;

string  dummy;
ubyte[] buff;

private long write_individual(ref Individual ii, char *w)
{
    ulong map_len = ii.resources.length + 1;
    char *w0 = w;
    w = mp_encode_array(w, 2);
    w = mp_encode_str(w, cast(char *)ii.uri.dup, cast(uint)ii.uri.length);
    w = mp_encode_map(w, cast(uint)ii.resources.length);

    foreach (key, resources; ii.resources)
        w = write_resources(key, resources, w, w0);
    
    return(w - cast (char*)buff.ptr);
}

private char *write_resources(string uri, ref Resources vv, char *w, char *w0)
{
    w = mp_encode_str(w, cast(char *)uri.dup, cast(uint)uri.length);
//           writefln("@d#1 mp_encode_str uri=[%s] len=[%d] w-w0=[%d]", uri.dup, uri.length, w-w0);

    w = mp_encode_array(w, cast(uint)vv.length);
//           writefln("@d#2 mp_encode_array len=[%d] w-w0=[%d]", vv.length, w-w0);

    foreach (value; vv)
    {
        if (value.type == DataType.Uri)
        {
            string svalue = value.get!string.dup;
            w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
        }
        else if (value.type == DataType.Integer)
        {
            w = mp_encode_uint(w, value.get!long);
        }
        else if (value.type == DataType.Datetime)
        {
            w = mp_encode_array(w, 2);
            w = mp_encode_uint(w, DataType.Datetime);
            w = mp_encode_uint(w, value.get!long);
        }
        else if (value.type == DataType.Decimal)
        {
            decimal x = value.get!decimal;

            w = mp_encode_array(w, 3);
            w = mp_encode_uint(w, DataType.Decimal);
            w = mp_encode_uint(w, x.mantissa);
            w = mp_encode_uint(w, x.exponent);
        }
        else if (value.type == DataType.Boolean)
        {
            w = mp_encode_bool(w, value.get!bool);
        }
        else
        {
            string svalue = value.get!string.dup;

            if (value.lang != LANG.NONE)
            {
                w = mp_encode_array(w, 3);
                w = mp_encode_uint(w, DataType.String);
                w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
                w = mp_encode_uint(w, value.lang);
            }
            else
            {
                w = mp_encode_array(w, 2);
                w = mp_encode_uint(w, DataType.String);
                w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
            }
        }
    }
    return w;
}

public string individual2msgpack(ref Individual in_obj)
{
    if (buff is null || buff.length == 0)
        buff = new ubyte[ 1024 * 1024 ];

    long len = write_individual(in_obj, cast (char*)buff.ptr);

    return cast(string)buff[ 0..len ].dup;
}

/////////////////////////////////////////////////////////////////////

public int msgpack2individual(ref Individual individual, string in_str)
{
    try
    {
        try
        {
            char *ptr         = cast(char *)in_str.ptr;
            int  root_el_size = mp_decode_array(&ptr);

            if (root_el_size != 2)
                return -1;

            uint uri_lenght;
            char *uri = mp_decode_str(&ptr, &uri_lenght);

            individual.uri = cast(string)uri[ 0..uri_lenght ].dup;

            int predicates_length = mp_decode_map(&ptr);
            for (int idx = 0; idx < predicates_length; idx++)
            {
                uint   key_lenght;
                char   *key      = mp_decode_str(&ptr, &key_lenght);
                string predicate = cast(string)key[ 0..key_lenght ].dup;

                Resources resources = Resources.init;

                int resources_el_length = mp_decode_array(&ptr);
                for (int i_resource = 0; i_resource < resources_el_length; i_resource++)
                {
                    mp_type el_type = mp_typeof(*ptr);

                    if (el_type == mp_type.MP_ARRAY)
                    {
                        int predicate_el_length = mp_decode_array(&ptr);
                        if (predicate_el_length == 2)
                        {
                            long type;

                            if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                type = mp_decode_uint(&ptr);
                            else
                                type = mp_decode_int(&ptr);

                            if (type == DataType.Datetime)
                            {
                                long value;
                                
                                if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                    value = mp_decode_uint(&ptr);
                                else
                                    value = mp_decode_int(&ptr);

                                resources ~= Resource(DataType.Datetime, value);
                            }
                            else if (type == DataType.String)
                            {
                                uint val_length;
                                string data;
                                if (mp_typeof(*ptr) != mp_type.MP_NIL) {
                                    char *val = mp_decode_str(&ptr, &val_length);
                                    data = val[ 0..val_length ].dup;
                                } else {
                                    mp_decode_nil(&ptr);
                                    data = "";
                                }
                                resources ~= Resource(DataType.String, data);
                            }
                            else
                                return -1;
                        }
                        else if (predicate_el_length == 3)
                        {
                            long type;

                            if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                type = mp_decode_uint(&ptr);
                            else
                                type = mp_decode_int(&ptr);

                            if (type == DataType.Decimal)
                            {
                                long mantissa, exponent;


                                if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                    mantissa = mp_decode_uint(&ptr);
                                else
                                    mantissa = mp_decode_int(&ptr);

                                if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                    exponent = mp_decode_uint(&ptr);
                                else
                                    exponent = mp_decode_int(&ptr);
                                
                                resources ~= Resource(decimal(mantissa, cast(byte)exponent));
                            }
                            else if (type == DataType.String)
                            {
                                uint val_length;
                                string data;

                                if (mp_typeof(*ptr) != mp_type.MP_NIL) {
                                    char *val = mp_decode_str(&ptr, &val_length);
                                    data = val[ 0..val_length ].dup;
                                } else {
                                    mp_decode_nil(&ptr);
                                    data = "";
                                }

                                long lang;
                                if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                                    lang = mp_decode_uint(&ptr);
                                else
                                    lang = mp_decode_int(&ptr);

                                resources ~= Resource(DataType.String, data, cast(LANG)lang);
                                
                            }
                            else
                                return -1;
                        }
                        else
                        {
                            writeln("@3");
                            return -1;
                        }
                    }
                    else if (el_type == mp_type.MP_STR)
                    {
                        uint val_length;
                        string data;
                        if (mp_typeof(*ptr) != mp_type.MP_NIL) {
                            char *val = mp_decode_str(&ptr, &val_length);
                            data = val[ 0..val_length ].dup;
                        } else {
                            mp_decode_nil(&ptr);
                            data = "";
                        }
                        resources ~= Resource(DataType.Uri, data);
                    }
                    else if (el_type == mp_type.MP_INT || el_type == mp_type.MP_UINT)
                    {
                        // this int
                        long val;
                        if (mp_typeof(*ptr) == mp_type.MP_UINT) 
                            val = mp_decode_uint(&ptr);
                        else
                            val = mp_decode_int(&ptr);
                        resources ~= Resource(DataType.Integer, val);
                    }
                    else if (el_type == mp_type.MP_BOOL)
                    {
                        // this bool
                        long val = mp_decode_bool(&ptr);
                        resources ~= Resource(DataType.Boolean, val);
                    }
                    else
                    {
                        writeln("@4 el_type=", text(cast(mp_type)el_type));
                        return -1;
                    }
                }
                
                if (resources.length == 0)
	                writeln ("ERR! msgpack2individual resources.length==0");
                
                individual.resources[ predicate ] = resources;
            }
            return cast(int)(ptr - cast(char *)in_str.ptr); //read_element(individual, cast(ubyte[])in_str, dummy);
        }
        catch (Throwable ex)
        {
            writeln("ERR! msgpack2individual ex=", ex.msg, ", in_str=", in_str);
            //printPrettyTrace(stderr);
            //throw new Exception("invalid binobj");
            return -1;
        }
    } finally
    {
        //writeln ("@d msgpack2individual @E");
    }
}
