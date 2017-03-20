/**
 * реализация хранилища, используя tarantool
 */
module veda.core.storage.tarantool_storage;

import veda.core.common.context, veda.common.logger;
import veda.connector.connector;

public class TarantoolStorage : Storage
{
	string host;
	int port;
    Logger              log;
    	
    this(string _host, int _port, Logger _log)
    {
    	host = _host;
    	port = _port;
        log  = _log;
    }	
	
    public ResultCode put(string in_key, string in_value, long op_id)
    {
    	log.trace ("ERR! put not implemented");
    	return ResultCode.Fail_Store;
    	//throw new Exception ("not implemented");
    }
    
    public string find(string uri, bool return_value = true)
    {
    	log.trace ("ERR! find not implemented");
    	return "";
    }
    
    public int get_of_cursor(bool delegate(string key, string value) prepare)
    {
    	log.trace ("ERR! get_of_cursor not implemented");
    	throw new Exception ("not implemented");    	    
    }
    
    public long count_entries()
    {
    	log.trace ("ERR! count_entries not implemented");
    	throw new Exception ("not implemented");    	
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
    	log.trace ("ERR! dump_to_binlog not implemented");
    	throw new Exception ("not implemented");    	
    }	

    public ResultCode remove(string in_key)
    {
    	log.trace ("ERR! remove not implemented");
    	throw new Exception ("not implemented");    	
    }	

}
