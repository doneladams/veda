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
    Connector connector;

    this(string _host, ushort _port, Logger _log)
    {
        host = _host;
        port = _port;
        log  = _log;
        connector = new Connector();
        connector.connect(this.host, this.port);
    	log.trace ("create TarantoolStorage connector");    	
    }

    public ResultCode put(string in_key, string in_value, long op_id)
    {
        RequestResponse rr = connector.put(false, null, [ in_value ]);

        if (rr !is null)
            return rr.common_rc;

        return ResultCode.Fail_Store;
    }

    public string find(string uri, bool return_value = true)
    {
        RequestResponse rr = connector.get(false, null, [ uri ]);

        if (rr !is null && rr.msgpacks.length > 0)
            return rr.msgpacks[ 0 ];

        return null;
    }

    public void unload_to_queue(string path, string queue_id, bool only_ids)
    {
    	
    }

    public int get_of_cursor(bool delegate(string key, string value) prepare, bool only_ids)
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
        connector.close();
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
