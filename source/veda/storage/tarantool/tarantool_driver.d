/**
 * реализация хранилища, используя немодифицированный tarantool
 */
module veda.storage.tarantool.tarantool_driver;

import core.thread, std.conv, std.stdio, std.string, std.conv, std.datetime.stopwatch, std.uuid, std.variant;
import veda.bind.tarantool.tnt_stream, veda.bind.tarantool.tnt_net, veda.bind.tarantool.tnt_opt, veda.bind.tarantool.tnt_ping;
import veda.bind.tarantool.tnt_reply, veda.bind.tarantool.tnt_insert, veda.bind.tarantool.tnt_delete, veda.bind.tarantool.tnt_object,
       veda.bind.tarantool.tnt_select;
import veda.util.properd, veda.bind.msgpuck;
import veda.common.logger, veda.common.type, veda.onto.lang;
import veda.onto.individual, veda.onto.resource;
import msgpack;
import veda.storage.common;
import std.digest.ripemd, std.digest.md;

public enum TTFIELD : ubyte
{
    HASH      = 0,
    SUBJECT   = 1,
    PREDICATE = 2,
    OBJECT    = 3,
    TYPE      = 4,
    LANG      = 5,
    ORDER     = 6
}

struct TripleRow
{
    long     id;
    string   subject;
    string   predicate;
    Variant  object;
    DataType type;
    LANG     lang;
    int      order;
}

tnt_stream *tnt         = null;
bool       db_is_opened = false;

public class TarantoolDriver : KeyValueDB
{
    Logger log;
    string db_uri;
    string space_name;
    int    space_id;

    this(Logger _log, string _space_name, int _space_id)
    {
        log = _log;
        string[ string ] properties;
        properties = readProperties("./veda.properties");
        db_uri     = properties.as!(string)("tarantool_url") ~ "\0";

        space_name = _space_name;
        space_id   = _space_id;
    }

    public static int INDEX_S = 1;

    public string get_binobj(string uri)
    {
        Individual indv;
        string     res = null;

        get_individual(uri, indv);

        if (indv.getStatus() == ResultCode.OK)
        {
            res = indv.serialize();
            //log.trace("@ get_binobj, uri=%s, indv=%s", uri, indv);
        }
        return res;
    }

    public void get_individual(string uri, ref Individual indv)
    {
        indv.setStatus(ResultCode.Unprocessable_Entity);

        if (uri is null || uri.length < 2)
        {
            indv.setStatus(ResultCode.Bad_Request);
            return;
        }

        if (db_is_opened != true)
        {
            open();
            if (db_is_opened != true)
            {
                indv.setStatus(ResultCode.Not_Ready);
                return;
            }
        }

        //log.trace("@%X %s get individual uri=[%s], space_id=%s", tnt, core.thread.Thread.getThis().name(), uri, text(space_id));

        tnt_reply_ reply;
        tnt_stream *tuple;

        try
        {
            tnt_reply_init(&reply);

            tuple = tnt_object(null);

            tnt_object_add_array(tuple, 1);
            tnt_object_add_str(tuple, cast(const(char)*)(uri ~ "\0"), cast(uint)uri.length);

            tnt_select(tnt, space_id, INDEX_S, 1024, 0, 0, tuple);
            tnt_flush(tnt);

            tnt.read_reply(tnt, &reply);

            //log.trace("@get individual @5 reply.code=[%d] uri=%s", reply.code, uri);
            if (reply.code != 0)
            {
                log.trace("Select [%s] failed, errcode=%s msg=%s", uri, reply.code, to!string(reply.error));
                if (reply.code == 36)
                    indv.setStatus(ResultCode.Not_Ready);
                else
                    indv.setStatus(ResultCode.Unprocessable_Entity);
                return;
            }

            mp_type field_type = mp_typeof(*reply.data);
            if (field_type != mp_type.MP_ARRAY)
            {
                log.trace("VALUE CONTENT INVALID FORMAT [], KEY=%s, field_type=%s", uri, field_type);
                indv.setStatus(ResultCode.Unprocessable_Entity);
                return;
            }

            uint tuple_count = mp_decode_array(&reply.data);
            if (tuple_count == 0)
            {
                //log.trace("ERR! not found ! request uri=[%s]", uri);
                indv.setStatus(ResultCode.Not_Found);
                return;
            }
            //log.trace ("@get individual @8 tuple_count=%d", tuple_count);

            string subject;

            for (int irow = 0; irow < tuple_count; ++irow)
            {
                field_type = mp_typeof(*reply.data);
                if (field_type != mp_type.MP_ARRAY)
                {
                    log.trace("VALUE CONTENT INVALID FORMAT [[]], KEY=%s, field_type=%s", uri, field_type);
                    indv.setStatus(ResultCode.Unprocessable_Entity);
                    return;
                }

                int    field_count = mp_decode_array(&reply.data);
                string predicate;
                string str_object;
                long   num_object;
                long   type  = 0;
                long   lang  = 0;
                int    order = 0;

                //log.trace("  field count=%d\n", field_count);
                for (int fidx = 0; fidx < field_count; ++fidx)
                {
                    long   num_value;
                    string value;

                    field_type = mp_typeof(*reply.data);
                    if (field_type == mp_type.MP_BOOL)
                    {
                        num_value = mp_decode_bool(&reply.data);
                        if (fidx == TTFIELD.OBJECT)
                            num_object = num_value;
                    }
                    else if (field_type == mp_type.MP_INT)
                    {
                        num_value = mp_decode_int(&reply.data);
                        if (fidx == TTFIELD.OBJECT)
                            num_object = num_value;
                    }
                    else if (field_type == mp_type.MP_UINT)
                    {
                        num_value = mp_decode_uint(&reply.data);
                        //log.trace("fidx=%d,    num value=%d\n", fidx, num_value);
                        if (fidx == TTFIELD.OBJECT)
                            num_object = num_value;
                        if (fidx == TTFIELD.ORDER)
                            order = cast(int)num_value;
                    }
                    else if (field_type == mp_type.MP_STR)
                    {
                        char *str_value;
                        uint str_value_length;
                        str_value = mp_decode_str(&reply.data, &str_value_length);
                        value     = cast(string)str_value[ 0..str_value_length ].dup;
                        //log.trace("fidx=%d,    str value=%s\n", fidx, cast(string)str_value[ 0..str_value_length ]);

                        if (fidx == cast(int)TTFIELD.OBJECT && str_object is null)
                            str_object = value;
                    }
                    else
                    {
                        log.trace("wrong field type\n");
                        //exit(1);
                    }

                    if (fidx == TTFIELD.SUBJECT && subject is null)
                    {
                        subject = value;

                        if (uri != subject)
                        {
                            log.trace("ERR! not found ?, request uri=%s, get uri=%s", uri, subject);
                            indv.setStatus(ResultCode.Not_Found);
                            return;
                        }

                        indv.uri = subject;
                    }

                    if (fidx == TTFIELD.PREDICATE && predicate is null)
                        predicate = value;

                    if (fidx == TTFIELD.TYPE && type == 0)
                        type = num_value;

                    if (fidx == TTFIELD.LANG && lang == 0)
                        lang = num_value;
                }

                if (type == DataType.Uri || type == DataType.String)
                {
                    Resource rr = Resource(cast(DataType)type, str_object, cast(LANG)lang);
                    rr.order = order;
                    indv.addResource(predicate, rr);
                }
                else if (type == DataType.Decimal)
                {
                    Resource rr = Resource(cast(DataType)type, str_object);
                    rr.order = order;
                    indv.addResource(predicate, rr);
                }
                else
                {
                    Resource rr = Resource(cast(DataType)type, num_object);
                    rr.order = order;
                    indv.addResource(predicate, rr);
                }
            }

            foreach (predicate; indv.resources.keys)
            {
                indv.reorder(predicate);
            }

            indv.setStatus(ResultCode.OK);
            //log.trace("driver:get:indv=%s", indv);

            //tnt_reply_free(&reply);
            //log.trace("@ TarantoolDriver.find: FOUND %s->[%s]", uri, cast(string)str_value[ 0..str_value_length ]);
        }
        finally
        {
            tnt_reply_free(&reply);

            if (tuple !is null)
                tnt_stream_free(tuple);
        }
    }

    private void update_row(string subject, string predicate, Value object, DataType type, LANG lang, int order, ref tnt_stream *[] tuples,
                            decimal num)
    {
        tnt_stream *tuple = tnt_object(null);

        tnt_object_add_array(tuple, 7);

        tnt_object_add_nil(tuple);

        tnt_object_add_str(tuple, cast(const(char)*)subject, cast(uint)subject.length);
        tnt_object_add_str(tuple, cast(const(char)*)predicate, cast(uint)predicate.length);

        if (type == DataType.Datetime || type == DataType.Integer)
        {
            if (object.type == Value.Type.unsigned)
                tnt_object_add_int(tuple, object.via.uinteger);
            else
                tnt_object_add_int(tuple, object.via.integer);
        }
        else if (type == DataType.Uri || type == DataType.String)
        {
            if (object.type == Value.type.nil)
            {
//            tnt_object_add_nil(tuple);
                tnt_object_add_str(tuple, cast(const(char)*)"", 0);
            }
            else
            {
                string str_obj = (cast(string)object.via.raw).dup;
                tnt_object_add_str(tuple, cast(const(char)*)str_obj, cast(uint)str_obj.length);
            }
        }
        else if (type == DataType.Boolean)
        {
            tnt_object_add_bool(tuple, object.via.boolean);
        }
        else if (type == DataType.Decimal)
        {
            string str_obj = num.asString();
            tnt_object_add_str(tuple, cast(const(char)*)str_obj, cast(uint)str_obj.length);
        }
        else
        {
            log.trace("ERR! update triple, unknown type %s", type);
        }


        tnt_object_add_int(tuple, type);
        tnt_object_add_int(tuple, lang);
        tnt_object_add_int(tuple, order);

        tnt_replace(tnt, space_id, tuple);

        tnt_flush(tnt);

        tnt_reply_ reply;
        tnt_reply_init(&reply);
        tnt.read_reply(tnt, &reply);
        if (reply.code != 0)
        {
            auto row = format("%s;%s;%s;%d;%d", subject, predicate, object, type, lang);
            log.trace("Insert failed errcode=%s msg=%s [%s]", reply.code, to!string(reply.error), row);
            tnt_reply_free(&reply);
            tnt_stream_free(tuple);
            return;        // ResultCode.Internal_Server_Error;
        }

        tnt_reply_free(&reply);
        tnt_stream_free(tuple);
    }

    ubyte magic_header = 146;

    public ResultCode store(string in_key, string in_str, long op_id)
    {
        string subject;

        //log.trace("@%X %s store uri=%s", tnt, core.thread.Thread.getThis().name(), in_key);

        if (db_is_opened != true)
        {
            open();
            if (db_is_opened != true)
                return ResultCode.Connect_Error;
        }

        if (in_str.length < 3)
            return ResultCode.Internal_Server_Error;

        tnt_stream *[] tuples;
        ubyte[]        src = cast(ubyte[])in_str;

        if (src[ 0 ] != magic_header)
        {
            log.trace("ERR! msgpack2individual: invalid format");
            return ResultCode.Internal_Server_Error;
        }

        if (src.length < 5)
        {
            log.trace("ERR! msgpack2individual: binobj is empty [%s]", src);
            return ResultCode.Internal_Server_Error;
        }

        TripleRow[] deleted_rows = get_individual_as_triple(in_key);
        if (deleted_rows.length > 0)
            remove_triple_rows(deleted_rows, in_key);

        try
        {
            try
            {
                StreamingUnpacker unpacker = StreamingUnpacker(src[ 0..$ ]);

                if (unpacker.execute())
                {
                    size_t root_el_size = unpacker.unpacked.length;
                    // writefln("TRY TO UNPACK root_el_size=%d", root_el_size);
                    if (root_el_size != 2)
                    {
                        log.trace("ERR! msgpack2individual: root_el_size != 2");
                        return ResultCode.Internal_Server_Error;
                    }

                    foreach (obj; unpacker.purge())
                    {
                        switch (obj.type)
                        {
                        case Value.Type.raw:
                            subject = (cast(string)obj.via.raw).dup;

                            break;

                        case Value.Type.map:

                            Value[ Value ] map = obj.via.map;
                            foreach (key; map.byKey)
                            {
                                string predicate = (cast(string)key.via.raw).dup;

//                            Resources resources      = Resources.init;
                                Value[] resources_vals = map[ key ].via.array;
                                // writeln("\t\tTRY UNPACK RESOURCES len ", resources_vals.length);
                                for (int i = 0; i < resources_vals.length; i++)
                                {
                                    // writeln("\t\t\tTRY UNPACK RESOURCES type ", resources_vals[i].type);
                                    switch (resources_vals[ i ].type)
                                    {
                                    case Value.Type.array:
                                        Value[] arr = resources_vals[ i ].via.array;
                                        if (arr.length == 2)
                                        {
                                            long type = arr[ 0 ].via.uinteger;

                                            update_row(subject, predicate, arr[ 1 ], cast(DataType)type, LANG.NONE, i, tuples, decimal.init);
                                        }
                                        else if (arr.length == 3)
                                        {
                                            long type = arr[ 0 ].via.uinteger;

                                            if (type == DataType.Decimal)
                                            {
                                                long mantissa, exponent;

                                                if (arr[ 1 ].type == Value.Type.unsigned)
                                                    mantissa = arr[ 1 ].via.uinteger;
                                                else
                                                    mantissa = arr[ 1 ].via.integer;

                                                if (arr[ 2 ].type == Value.Type.unsigned)
                                                    exponent = arr[ 2 ].via.uinteger;
                                                else
                                                    exponent = arr[ 2 ].via.integer;

                                                update_row(subject, predicate, Value.init, cast(DataType)type, LANG.NONE,
                                                           i, tuples, decimal(mantissa, cast(byte)exponent));
                                            }
                                            else if (type == DataType.String)
                                            {
                                                long lang = arr[ 2 ].via.uinteger;
                                                update_row(subject, predicate, arr[ 1 ], cast(DataType)type, cast(LANG)lang,
                                                           i, tuples, decimal.init);
                                            }
                                            else
                                            {
                                                log.trace("ERR! msgpack2individual: [0][1][3] unknown type [%d]", type);
                                                return ResultCode.Internal_Server_Error;
                                            }
                                        }
                                        break;

                                    default:
                                        log.trace("ERR! msgpack2individual: unknown type [%d]", resources_vals[ i ].type);
                                        break;
                                    }
                                }
                                //individual.resources[ predicate ] = resources;
                            }
                            break;

                        default:
                            break;
                        }
                    }
                }
                else
                {
                    log.trace("ERR! msgpack2individual: binobj is invalid! src=[%s]", in_str);
                    return ResultCode.Internal_Server_Error;
                }

                if (tnt_flush(tnt) < 0)
                {
                    log.trace("Insert failed network error [%s][%s]", in_key, in_str);
                    return ResultCode.Internal_Server_Error;
                }
/*
                tnt_reply_ reply;
                tnt_reply_init(&reply);
                tnt.read_reply(tnt, &reply);
                if (reply.code != 0)
                {
                    log.trace("Insert failed errcode=%s msg=%s [%s][%s]", reply.code, to!string(reply.error), in_key, in_str);
                    tnt_reply_free(&reply);
                    return ResultCode.Internal_Server_Error;
                }

                tnt_reply_free(&reply);
 */
                //log.trace ("@%X END, store uri=%s", tnt, in_key);

                //tnt_flush (tnt);
                //reopen ();

                return ResultCode.OK;
                // return cast(int)(ptr - cast(char *)in_str.ptr); //read_element(individual, cast(ubyte[])in_str, dummy);
            }
            catch (Throwable ex)
            {
                log.trace("ERR! msgpack2individual ex=", ex.msg, ", in_str=", in_str);
                //throw new Exception("invalid binobj");
                return ResultCode.Internal_Server_Error;
            }
        } finally
        {
//                foreach (tuple; tuples)
//                {
//					log.trace ("@ free tuple");
//
//                    tnt_stream_free(tuple);
//				}
//            log.trace ("@d msgpack2individual @E");
        }
    }

    private TripleRow[] get_individual_as_triple(string in_key)
    {
        TripleRow[] res;

        tnt_reply_  reply;
        tnt_stream  *tuple;

        try
        {
            tnt_reply_init(&reply);

            tuple = tnt_object(null);

            tnt_object_add_array(tuple, 1);
            tnt_object_add_str(tuple, cast(const(char)*)in_key, cast(uint)in_key.length);

            tnt_select(tnt, space_id, INDEX_S, 1024, 0, 0, tuple);
            tnt_flush(tnt);

            tnt.read_reply(tnt, &reply);

            //log.trace("@remove individual @5 reply.code=[%d]", reply.code);
            if (reply.code != 0)
            {
                log.trace("Select [%s] failed, errcode=%s msg=%s", in_key, reply.code, to!string(reply.error));
                return res;
            }

            mp_type field_type = mp_typeof(*reply.data);
            if (field_type != mp_type.MP_ARRAY)
            {
                log.trace("VALUE CONTENT INVALID FORMAT [], KEY=%s, field_type=%s", in_key, field_type);

                return res;
            }

            uint tuple_count = mp_decode_array(&reply.data);
            if (tuple_count == 0)
            {
                //log.trace("ERR! remove individual, not found ! request uri=%s", in_key);
                return res;
            }
            //log.trace("@remove individual, @8 tuple_count=%d", tuple_count);

            string subject;

            for (int irow = 0; irow < tuple_count; ++irow)
            {
                field_type = mp_typeof(*reply.data);
                if (field_type != mp_type.MP_ARRAY)
                {
                    log.trace("VALUE CONTENT INVALID FORMAT [[]], KEY=%s, field_type=%s", in_key, field_type);
                    return res;
                }

                int field_count = mp_decode_array(&reply.data);

                for (int fidx = 0; fidx < field_count; ++fidx)
                {
                    field_type = mp_typeof(*reply.data);
                    if (field_type == mp_type.MP_BOOL)
                    {
                        mp_decode_bool(&reply.data);
                    }
                    else if (field_type == mp_type.MP_INT)
                    {
                        mp_decode_int(&reply.data);
                    }
                    else if (field_type == mp_type.MP_UINT)
                    {
                        auto uid = mp_decode_uint(&reply.data);

                        if (fidx == cast(int)TTFIELD.HASH)
                        {
                            TripleRow tr;
                            tr.id = uid;
                            res ~= tr;
                        }
                    }
                    else if (field_type == mp_type.MP_STR)
                    {
                        char *str_value;
                        uint str_value_length;
                        //str_value =
                        mp_decode_str(&reply.data, &str_value_length);

                        //if (fidx == cast(int)TTFIELD.HASH)
                        //    deleted_ids ~= cast(string)str_value[ 0..str_value_length ].dup;
                    }
                    else
                    {
                        log.trace("wrong field type\n");
                        //exit(1);
                    }
                }
            }
            return res;
        }
        finally
        {
            tnt_reply_free(&reply);

            if (tuple !is null)
                tnt_stream_free(tuple);
        }
    }

    private void remove_triple_rows(TripleRow[] rows, string in_key)
    {
        //log.trace("deleted_rows=%s", rows);

        foreach (row; rows)
        {
            tnt_stream *tuple;
            tnt_reply_ reply;

            //log.trace("row=%s", row);
            tuple = tnt_object(null);
            tnt_object_add_array(tuple, 1);

            //tnt_object_add_str(tuple, cast(const(char)*)id, cast(uint)id.length);
            tnt_object_add_int(tuple, row.id);

            tnt_delete(tnt, space_id, 0, tuple);
            tnt_flush(tnt);
            tnt_stream_free(tuple);

            tnt_reply_init(&reply);
            tnt.read_reply(tnt, &reply);
            if (reply.code != 0)
            {
                log.trace("Remove failed [%s] id=[%s], errcode=%s msg=%s", in_key, row.id, reply.code, to!string(reply.error));
                //tnt_reply_free(&reply);
                //return;
            }
            //else
            //{
            //log.trace("Remove Ok [%s] id=[%s]", in_key, row.id);
            //}

            tnt_reply_free(&reply);
        }
    }

    public ResultCode remove(string in_key)
    {
        if (db_is_opened != true)
        {
            open();
            if (db_is_opened != true)
                return ResultCode.Connect_Error;
        }

        //log.trace("@%X %s remove individual uri=%s", tnt, core.thread.Thread.getThis().name(), in_key);

        TripleRow[] deleted_rows = get_individual_as_triple(in_key);
        if (deleted_rows.length > 0)
            remove_triple_rows(deleted_rows, in_key);

        return ResultCode.OK;
    }

    public long get_last_op_id()
    {
        return -1;
    }

    public void open()
    {
        if (db_is_opened == false)
        {
            tnt = tnt_net(null);

            tnt_set(tnt, tnt_opt_type.TNT_OPT_URI, db_uri.ptr);
            tnt_set(tnt, tnt_opt_type.TNT_OPT_SEND_BUF, 0);
            tnt_set(tnt, tnt_opt_type.TNT_OPT_RECV_BUF, 0);
            int res = tnt_connect(tnt);
            if (res == 0)
            {
                tnt_ping(tnt);
                tnt_reply_ *reply = tnt_reply_init(null);
                tnt.read_reply(tnt, reply);
                tnt_reply_free(reply);
                if (reply.code == 0)
                {
                    // CHECK EXISTS SPACE
                    tnt_reply_init(reply);

                    tnt_stream *tuple = tnt_object(null);

                    tnt_object_add_array(tuple, 1);
                    tnt_object_add_int(tuple, 0);

                    tnt_select(tnt, space_id, 0, (2 ^ 32) - 1, 0, 0, tuple);
                    tnt_flush(tnt);
                    tnt_stream_free(tuple);

                    tnt.read_reply(tnt, reply);
                    if (reply.code == 36)
                    {
                        tnt_reply_free(reply);
                        log.trace("ERR! SPACE %s NOT FOUND", space_name);
                        log.trace("SLEEP AND REPEAT");
                        core.thread.Thread.sleep(dur!("seconds")(1));
                        return open();
                    }
                    else
                        tnt_reply_free(reply);


                    log.trace("SUCCESS CONNECT TO TARANTOOL %s", db_uri);
                    db_is_opened = true;
                }
            }
            else
            {
                log.trace("FAIL CONNECT TO TARANTOOL %s err=%s", db_uri, to!string(tnt_strerror(tnt)));
                log.trace("SLEEP AND REPEAT");
                core.thread.Thread.sleep(dur!("seconds")(1));
                return open();
            }
        }
    }

    public void reopen()
    {
//close();
//open();
    }

    public void close()
    {
//if (db_is_opened == true) {
//		tnt_close(tnt);
//      tnt_stream_free(tnt);
//      db_is_opened = false;
//	}
    }

    public long count_entries()
    {
        return -1;
    }

    public void flush(int force)
    {
    }
}
