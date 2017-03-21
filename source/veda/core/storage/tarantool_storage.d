/**
 * реализация хранилища, используя tarantool
 */
module veda.core.storage.tarantool_storage;

import veda.core.common.context, veda.common.logger;
import veda.connector.connector;
import veda.connector.requestresponse;

public class TarantoolStorage : Storage
{
    string host;
    ushort port;
    Logger log;

    this(string _host, ushort _port, Logger _log)
    {
        host = _host;
        port = _port;
        log  = _log;
    	log.trace ("(0 create TarantoolStorage");    	
    }

    public ResultCode put(string in_key, string in_value, long op_id)
    {
        RequestResponse rr = Connector.put(host, port, false, null, [ in_value ]);

        if (rr !is null)
            return rr.common_rc;

        return ResultCode.Fail_Store;
    }

    public string find(string uri, bool return_value = true)
    {
    	log.trace ("(1");    	
        RequestResponse rr = Connector.get(host, port, false, null, [ uri ]);
    	log.trace ("(2");    	

        if (rr !is null && rr.msgpacks.length > 0)
            return rr.msgpacks[ 0 ];

        return null;
    }

    public int get_of_cursor(bool delegate(string key, string value) prepare)
    {
        log.trace("ERR! get_of_cursor not implemented");
        throw new Exception("not implemented");
    }

    public long count_entries()
    {
        log.trace("ERR! count_entries not implemented");
        throw new Exception("not implemented");
    }

    public void reopen_db()
    {
        //throw new Exception ("not implemented");
    }

    public void close_db()
    {
        //throw new Exception ("not implemented");
    }

    public long dump_to_binlog()
    {
        log.trace("ERR! dump_to_binlog not implemented");
        throw new Exception("not implemented");
    }

    public ResultCode remove(string in_key)
    {
        log.trace("ERR! remove not implemented");
        throw new Exception("not implemented");
    }
}
