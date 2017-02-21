/**
 * msgpack -> vibe.d json

   Copyright: © 2014-2017 Semantic Machines
   License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
   Authors: Valeriy Bushenev
 */

module veda.frontend.msgpack8vjson;

private import msgpack;
private import std.outbuffer, std.stdio, std.string, std.conv, std.datetime;
private import vibe.data.json;
private import veda.common.type, veda.onto.resource, veda.onto.individual, veda.onto.lang, veda.bind.msgpuck;

public int msgpack2vjson(Json *individual, string in_str)
{
    try
    {
        StreamingUnpacker unpacker = StreamingUnpacker(cast(ubyte[])in_str);

        if (unpacker.execute()) 
        {      
            size_t root_el_size = unpacker.unpacked.length;
            if (root_el_size != 2)
                return -1;
            
            foreach (obj; unpacker.purge()) 
            {
                switch (obj.type) 
                {
                    case Value.Type.raw:
                    (*individual)[ "@" ] = (cast(string)obj.via.raw).dup;
                    break;

                    case Value.Type.map:
                    Value[Value] map = obj.via.map;
                    foreach (key; map.byKey) 
                    {
                        string predicate = (cast(string)key.via.raw).dup;
                        
                        stderr.writeln ("predicate=", predicate);
                        
                        Value[] resources_vals = map[key].via.array;
                        Json   resources = Json.emptyArray;
                        
                        for (int i = 0; i < resources_vals.length; i++) 
                        {
                            Json resource_json = Json.emptyObject;                        
                            switch (resources_vals[i].type)
                            {
                                case Value.Type.array:
                                Value[] arr = resources_vals[i].via.array;
                                if (arr.length == 2)
                                {
                                    long type = arr[0].via.uinteger;

                                    if (type == DataType.Datetime)
                                    {
                                        long value;
                            
                                        if (arr[1].type == Value.Type.unsigned)
                                            value = arr[1].via.uinteger;
                                        else 
                                            value = arr[1].via.integer;

                                        resource_json[ "type" ] = text(DataType.Datetime);
                                        SysTime st = SysTime(unixTimeToStdTime(value), UTC());
                                        resource_json[ "data" ] = st.toISOExtString();
                                    }
                                    else if (type == DataType.String)
                                    {  
                                        if (arr[1].type == Value.type.raw)
                                            resource_json[ "data" ] = 
                                                (cast(string)arr[1].via.raw).dup;
                                        else if (arr[1].type == Value.type.nil)
                                            resource_json[ "data" ] = "";

                                        resource_json[ "lang" ] = text(LANG.NONE);
                                        resource_json[ "type" ] = text(DataType.String);
                                    }
                                    else
                                    {
                                        stderr.writeln("@1");
                                        return -1;
                                    }
                                }
                                else if (arr.length == 3)
                                {
                                    long type = arr[0].via.uinteger;

                                    if (type == DataType.Decimal)
                                    {
                                        long mantissa, exponent;

                                        if (arr[1].type == Value.Type.unsigned)
                                            mantissa = arr[1].via.uinteger;
                                        else 
                                            mantissa = arr[1].via.integer;

                                        if (arr[2].type == Value.Type.unsigned)
                                            exponent = arr[2].via.uinteger;
                                        else 
                                            exponent = arr[2].via.integer;

                                        resource_json[ "type" ] = text(DataType.Decimal);
                                        auto dres = decimal(mantissa, cast(byte)exponent);
                                        resource_json[ "data" ] = dres.asString();
                                    }
                                    else if (type == DataType.String)
                                    {
                                        if (arr[1].type == Value.type.raw)
                                            resource_json[ "data" ] = 
                                                (cast(string)arr[1].via.raw).dup;
                                        else if (arr[1].type == Value.type.nil)
                                            resource_json[ "data" ] = "";

                                        resource_json[ "type" ] = text(DataType.String);
                                        resource_json[ "lang" ] = 
                                            text(cast(LANG)arr[2].via.uinteger);
                                    }
                                    else
                                    {
                                        stderr.writeln("@2");
                                        return -1;
                                    }
                                }
                                break;

                                case Value.Type.raw:
                                // writeln("\t\t\t\t", cast(string)resources_vals[i].via.raw);
                                resource_json[ "type" ] = text(DataType.Uri);
                                resource_json[ "data" ] = 
                                    (cast(string)resources_vals[i].via.raw).dup;
                                break;

                                case Value.Type.unsigned:
                                    resource_json[ "type" ] = text(DataType.Integer);
                                    resource_json[ "data" ] = resources_vals[i].via.uinteger;
                                break;

                                case Value.Type.signed:
                                resource_json[ "type" ] = text(DataType.Integer);
                                resource_json[ "data" ] = resources_vals[i].via.integer;
                                break;


                                case Value.Type.boolean:
                                resource_json[ "type" ] = text(DataType.Boolean);
                                resource_json[ "data" ] = resources_vals[i].via.boolean;
                                break;

                                default:
                                    stderr.writefln("@ERR! UNSUPPORTED TYPE IN MSGPACK!");
                                break;
                            }
                            resources ~= resource_json;
                            
                        }   
                        
                        (*individual)[ predicate ] = resources;                     
                    }
                    break;

                    default:
                    break;
                }
            }
        } 
        else 
        {
                stderr.writeln("Serialized object is too large!");
                return -1;
        }

        stderr.writeln("msgpack2vjson: JSON: ", *individual);

        return 1; //read_element(individual, cast(ubyte[])in_str, dummy);
    }
    catch (Throwable ex)
    {
        writeln("ERR! msgpack2individual ex=", ex.msg, ", in_str=", in_str);
        //printPrettyTrace(stderr);
        //throw new Exception("invalid binobj");
        return -1;
    }
}
