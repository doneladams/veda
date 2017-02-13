/**
 * msgpack <-> individual

   Copyright: © 2014-2017 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */

module veda.onto.bj8individual.msgpack8individual;

private import std.outbuffer, std.stdio, std.string, std.conv;
private import veda.common.type, veda.onto.resource, veda.onto.individual, veda.onto.lang, veda.bind.msgpuck;
//import backtrace.backtrace;
//import Backtrace = backtrace.backtrace;

string  dummy;
ubyte[] buff;

private long write_individual(ref Individual ii, char *w)
{
//           writefln("@d#0 ---------------- ii=\n%s", ii);

    ulong map_len = ii.resources.length + 1;
char *w0 = w;
    w = mp_encode_array(w, 2);
//           writefln("@d#0 mp_encode_array len=[%d] w-w0=[%d]", 2, w-w0);
    w = mp_encode_str(w, cast(char *)ii.uri.dup, cast(uint)ii.uri.length);
//           writefln("@d#0 mp_encode_str uri=[%s] len=[%d] w-w0=[%d]", ii.uri.dup, ii.uri.length, w-w0);

//    int count;
//    foreach (key, resources; ii.resources)
//    {
//        if (resources.length > 0)
//            count++;
//    }

    w = mp_encode_map(w, cast(uint)ii.resources.length);
//           writefln("@d#0 mp_encode_map len=[%d] w-w0=[%d]", ii.resources.length, w-w0);

    foreach (key, resources; ii.resources)
    {
//        if (resources.length > 0)
//        if (resources.length == 0)
//            writeln("@d RESOURCE LEN==0");
//writefln ("@d $1 *w=%X", w);
        w = write_resources(key, resources, w, w0);
//writefln ("@d $2 *w=%X", w);
    }
    
    //writeln (buff[0..(w - cast (char*)buff.ptr)]);
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
//    	writefln("@d#2.1 value=%s", value);
    	
        if (value.type == DataType.Uri)
        {
            string svalue = value.get!string.dup;
            w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
//           writefln("@d#3 mp_encode_str str=[%s] len=[%d] w-w0=[%d]", svalue, svalue.length, w-w0);
        }
        else if (value.type == DataType.Integer)
        {
            w = mp_encode_uint(w, value.get!long);
//           writefln("@d#4 mp_encode_uint value=[%d] w-w0=[%d]", value.get!long, w-w0);
        }
        else if (value.type == DataType.Datetime)
        {
            w = mp_encode_array(w, 2);
//           writefln("@d#5 mp_encode_array len=[%d] w-w0=[%d]", 2, w-w0);
            w = mp_encode_uint(w, DataType.Datetime);
//           writefln("@d#6 mp_encode_uint value=[%d] w-w0=[%d]", DataType.Datetime, w-w0);
            w = mp_encode_uint(w, value.get!long);
//           writefln("@d#7 mp_encode_uint value=[%d] w-w0=[%d]", value.get!long, w-w0);
        }
        else if (value.type == DataType.Decimal)
        {
            decimal x = value.get!decimal;

            w = mp_encode_array(w, 3);
//           writefln("@d#8 mp_encode_array len=[%d] w-w0=[%d]", 3, w-w0);
            w = mp_encode_uint(w, DataType.Decimal);
//           writefln("@d#9 mp_encode_uint value=[%d] w-w0=[%d]", DataType.Decimal, w-w0);
            w = mp_encode_uint(w, x.mantissa);
//           writefln("@d#a mp_encode_uint value=[%d] w-w0=[%d]", x.mantissa, w-w0);
            w = mp_encode_uint(w, x.exponent);
//           writefln("@d#b mp_encode_uint value=[%d] w-w0=[%d]", x.exponent, w-w0);
        }
        else if (value.type == DataType.Boolean)
        {
            w = mp_encode_bool(w, value.get!bool);
//           writefln("@d#c mp_encode_bool value=[%d] w-w0=[%d]", value.get!bool, w-w0);
        }
        else
        {
            string svalue = value.get!string.dup;

            if (value.lang != LANG.NONE)
            {
                w = mp_encode_array(w, 3);
//           writefln("@d#d mp_encode_array len=[%d] w-w0=[%d]", 3, w-w0);
                w = mp_encode_uint(w, DataType.String);
//           writefln("@d#e mp_encode_uint value=[%d] w-w0=[%d]", DataType.String, w-w0);
                w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
//           writefln("@d#f mp_encode_str str=[%s] len=[%d] w-w0=[%d]", svalue, svalue.length, w-w0);
                w = mp_encode_uint(w, value.lang);
//           writefln("@d#e mp_encode_uint value=[%d] w-w0=[%d]", value.lang, w-w0);
            }
            else
            {
                w = mp_encode_array(w, 2);
//           writefln("@d#d mp_encode_array len=[%d] w-w0=[%d]", 2, w-w0);
                w = mp_encode_uint(w, DataType.String);
//           writefln("@d#e mp_encode_uint value=[%d] w-w0=[%d]", DataType.String, w-w0);
                w = mp_encode_str(w, cast(char *)svalue, cast(uint)svalue.length);
//           writefln("@d#f mp_encode_str str=[%s] len=[%d] w-w0=[%d]", svalue, svalue.length, w-w0);
            }
        }
    }
//           writefln("@d#e w-w0=[%d] w0=%X w=%X", w-w0, w0, w);
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
            //writefln ("@d msgpack2individual in_str=[%s]", in_str);

            char *ptr         = cast(char *)in_str.ptr;
            int  root_el_size = mp_decode_array(&ptr);

            if (root_el_size != 2)
                return -1;

            uint uri_lenght;
            char *uri = mp_decode_str(&ptr, &uri_lenght);
            individual.uri = cast(string)uri[ 0..uri_lenght ].dup;

            //writeln ("@d msgpack2individual uri=", individual.uri);

            int predicates_length = mp_decode_map(&ptr);

            //writeln ("@d msgpack2individual predicates_length=", predicates_length);

            for (int idx = 0; idx < predicates_length; idx++)
            {
                //writeln ("@d msgpack2individual idx=", idx);

              //      mp_type el_type = mp_typeof(*ptr);
              //      writeln ("@0.0 msgpack2individual el_type=", text (cast(mp_type)el_type));

                uint   key_lenght;
                char   *key      = mp_decode_str(&ptr, &key_lenght);
                string predicate = cast(string)key[ 0..key_lenght ].dup;

                //writeln ("@d msgpack2individual predicate=", predicate);

                Resources resources = Resources.init;

                int       resources_el_length = mp_decode_array(&ptr);
                for (int i_resource = 0; i_resource < resources_el_length; i_resource++)
                {
                    mp_type el_type = mp_typeof(*ptr);
                    //writeln ("@0 msgpack2individual el_type=", text (cast(mp_type)el_type));

                    if (el_type == mp_type.MP_ARRAY)
                    {
                        int predicate_el_length = mp_decode_array(&ptr);
                        if (predicate_el_length == 2)
                        {
                            long type = mp_decode_uint(&ptr);

                            if (type == DataType.Datetime)
                            {
                                long value = mp_decode_uint(&ptr);
                                resources ~= Resource(DataType.Datetime, value);
                            }
                            else if (type == DataType.String)
                            {
                                uint val_length;
                                char *val = mp_decode_str(&ptr, &val_length);
                                resources ~= Resource(DataType.String, cast(string)val[ 0..val_length ].dup);
                            }
                            else
                            {
                                writeln("@1");
                                return -1;
                            }
                        }
                        else if (predicate_el_length == 3)
                        {
                            long type = mp_decode_uint(&ptr);

                            if (type == DataType.Decimal)
                            {
                                long mantissa = mp_decode_uint(&ptr);
                                long exponent = mp_decode_uint(&ptr);
                                resources ~= Resource(decimal(mantissa, cast(byte)exponent));
                            }
                            else if (type == DataType.String)
                            {
                                uint val_length;
                                char *val = mp_decode_str(&ptr, &val_length);
                                long lang = mp_decode_uint(&ptr);
                                resources ~= Resource(DataType.String, cast(string)val[ 0..val_length ].dup, cast(LANG)lang);
                            }
                            else
                            {
                                writeln("@2");
                                return -1;
                            }
                        }
                        else
                        {
                            writeln("@3");
                            return -1;
                        }
                    }
                    else if (el_type == mp_type.MP_STR)
                    {
                        // this uri
                        uint val_length;
                        char *val = mp_decode_str(&ptr, &val_length);
                        resources ~= Resource(DataType.Uri, cast(string)val[ 0..val_length ].dup);
                    }
                    else if (el_type == mp_type.MP_INT || el_type == mp_type.MP_UINT)
                    {
                        // this int
                        long val = mp_decode_uint(&ptr);
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
