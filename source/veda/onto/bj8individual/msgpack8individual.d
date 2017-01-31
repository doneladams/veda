/**
 * msgpack <-> individual

   Copyright: © 2014-2017 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */

module veda.onto.bj8individual.msgpack8individual;

private import std.outbuffer, std.stdio, std.string;
private import veda.common.type, veda.onto.resource, veda.onto.individual, veda.onto.lang, veda.bind.msgpuck;
import backtrace.backtrace;
import Backtrace = backtrace.backtrace;

string  dummy;
ubyte[] buff;

private long write_individual(Individual *ii, char *w)
{
    ulong map_len = ii.resources.length + 1;

    w = mp_encode_array(w, 2);
    w = mp_encode_str(w, cast(char *)ii.uri, cast(uint)ii.uri.length);

    int count;
    foreach (key, resources; ii.resources)
    {
        if (resources.length > 0)
            count++;
    }

    w = mp_encode_map(w, count);

    foreach (key, resources; ii.resources)
    {
        if (resources.length > 0)
            w = write_resources(key, resources, w);
    }
    return(w - cast(char *)buff);
}

private char *write_resources(string uri, ref Resources vv, char *w)
{
    w = mp_encode_str(w, cast(char *)uri, cast(uint)uri.length);

    if (vv.length > 1)
        w = mp_encode_array(w, cast(uint)vv.length);

    foreach (value; vv)
    {
        if (value.type == DataType.Uri)
        {
            string svalue = value.get!string;
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
            string svalue = value.get!string;

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

public ubyte[] individual2msgpack(Individual *in_obj)
{
    if (buff is null)
        buff = new ubyte[ 1024 * 1024 ];

    long len = write_individual(in_obj, cast(char *)buff);

    return buff[ 0..len ];
}

/////////////////////////////////////////////////////////////////////

public int msgpack2individual(Individual *individual, string in_str)
{
    try
    {
    	char *ptr = cast(char*)in_str.ptr;
    	int size = mp_decode_array(&ptr);
    	
    	if (size != 2)
	    	return -1;
	    	
	    uint uri_lenght; 	
	    char *uri = mp_decode_str(&ptr, &uri_lenght);
	
    	
        return -1;//read_element(individual, cast(ubyte[])in_str, dummy);
    }
    catch (Throwable ex)
    {
        writeln("ERR! msgpack2individual ex=", ex.msg, ", in_str=", in_str);
        //printPrettyTrace(stderr);
        //throw new Exception("invalid cbor");
        return -1;
    }
}
