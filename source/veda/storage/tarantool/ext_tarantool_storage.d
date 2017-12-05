/**
 * реализация хранилища, используя tarantool
 */
module veda.storage.tarantool.ext_tarantool_storage;

import std.conv, std.stdio, std.string;
import veda.core.common.context, veda.common.logger, veda.common.type;
import veda.storage.tarantool.storage_connector, veda.storage.tarantool.requestresponse, veda.storage.common;
import veda.core.common.transaction, veda.onto.individual, veda.onto.resource;
import veda.util.properd;

public class ExtTarantoolStorage
{
    string                    host;
    ushort                    port;
    Logger                    log;
    public ExtTarantoolConnector connector;	

    this(string _host, ushort _port, Logger _log)
    {
        try
        {
            host      = _host;
            port      = _port;
            log       = _log;
            connector = new ExtTarantoolConnector(log);
            connector.connect(this.host, this.port);
            log.trace("sucess create TarantoolStorage connector %s:%d", host, port);
        }
        catch (Throwable tr)
        {
            log.trace("ERR! fail create TarantoolStorage connector, infp=%s", tr.msg);
        }
    }

    this(Logger _log)
    {
        string[ string ] properties;
        properties = readProperties("./veda.properties");
        string   tt_url = properties.as!(string)("tarantool_url");

        string[] tt_pp = tt_url.split(":");

        try
        {
            host      = tt_pp[ 0 ];
            port      = std.conv.to!ushort (tt_pp[ 1 ]);
            log       = _log;
            connector = new ExtTarantoolConnector(log);
            connector.connect(this.host, this.port);
            log.trace("sucess create TarantoolStorage connector %s:%d", host, port);
        }
        catch (Throwable tr)
        {
            log.trace("ERR! fail create TarantoolStorage connector, infp=%s", tr.msg);
        }        
    }

    public OpResult put(OptAuthorize op_auth, TransactionItem ti)
    {
        RequestResponse rr = connector.put(op_auth, ti.user_uri, ti2binobj([ ti ]));

        return OpResult(rr.common_rc, ti.op_id);
    }

    public OpResult put(OptAuthorize op_auth, immutable TransactionItem ti)
    {
        RequestResponse rr = connector.put(op_auth, ti.user_uri, ti2binobj([ ti ]));

        return OpResult(rr.common_rc, ti.op_id);
    }

    public OpResult[] put(OptAuthorize op_auth, TransactionItem[] items)
    {
        OpResult[]      rcs;

        RequestResponse lres = connector.put(op_auth, items[ 0 ].user_uri, ti2binobj(items));

        foreach (idx, rr; lres.op_rc)
            rcs ~= OpResult(lres.op_rc[ idx ], items[ idx ].op_id);

        return rcs;
    }

    public OpResult[] put(OptAuthorize op_auth, immutable(TransactionItem)[] items)
    {
        OpResult[]      rcs;

        RequestResponse lres = connector.put(op_auth, items[ 0 ].user_uri, ti2binobj(items));

        foreach (idx, rr; lres.op_rc)
            rcs ~= OpResult(lres.op_rc[ idx ], items[ idx ].op_id);

        return rcs;
    }

    public ResultCode remove(OptAuthorize op_auth, string user_uri, string in_key)
    {
        RequestResponse rr = connector.remove(op_auth, user_uri, [ in_key ], false);

        if (rr !is null)
            return rr.common_rc;

        return ResultCode.Fail_Store;
    }

    public string find(OptAuthorize op_auth, string user_uri, string uri, bool return_value = true)
    {
        // stderr.writefln("@FIND [%s] [%s]", user_uri, uri);
        RequestResponse rr = connector.get(op_auth, user_uri, [ uri ], false);

        // stderr.writefln("@FIND RETURN FROM CONNECTOR");
        if (rr !is null && rr.binobjs.length > 0)
        {
            return rr.binobjs[ 0 ];
        }

        return null;
    }

    public string find_ticket(string ticket_id)
    {
        RequestResponse rr = connector.get_ticket([ ticket_id ], false);

        if (rr !is null && rr.binobjs.length > 0)
            return rr.binobjs[ 0 ];

        return null;
    }

    public ubyte authorize(string user_uri, string uri, bool trace)
    {
        // stderr.writefln("@AUTH [%s] [%s]", user_uri, uri);
        RequestResponse rr = connector.authorize(user_uri, [ uri ], trace);

        //log.trace ("authorize.common_rc = %s", rr.common_rc);

        if (rr.common_rc == ResultCode.OK)
        {
            // log.trace ("authorize.right=%s", access_to_pretty_string (rr.rights[0]));

            if (rr !is null && rr.rights.length > 0)
                return rr.rights[ 0 ];
        }

        return 0;
    }

    public void reopen()
    {
    }

    public void open()
    {
    }

    public void close()
    {
    }

    long count_entries()
    {
        return -1;
    }
}

string[] ti2binobj(immutable (TransactionItem)[] items)
{
    string[] ipack;

    foreach (ti; items)
    {
        Individual imm;
        imm.uri = text(ti.op_id);

        if (ti.prev_binobj !is null && ti.prev_binobj.length > 0)
            imm.addResource("prev_state", Resource(DataType.String, ti.prev_binobj));
        imm.addResource("new_state", Resource(DataType.String, ti.new_binobj));

        ipack ~= imm.serialize_to_msgpack();
    }

    return ipack;
}

string[] ti2binobj(TransactionItem[] items)
{
    string[] ipack;

    foreach (ti; items)
    {
        Individual imm;
        imm.uri = text(ti.op_id);

        if (ti.prev_binobj !is null && ti.prev_binobj.length > 0)
            imm.addResource("prev_state", Resource(DataType.String, ti.prev_binobj));
        imm.addResource("new_state", Resource(DataType.String, ti.new_binobj));

        ipack ~= imm.serialize_to_msgpack();
    }

    return ipack;
}