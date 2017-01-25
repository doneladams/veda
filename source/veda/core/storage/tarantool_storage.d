/**
 * реализация хранилища, используя tarantool
 */
module veda.core.storage.tarantool_storage;

import veda.core.common.context;

public class LmdbStorage : Storage
{
    public ResultCode put(string in_key, string in_value, long op_id)
    {
    	throw new Exception ("not implemented");
    }
    
    public string find(string uri, bool return_value = true)
    {
    	throw new Exception ("not implemented");    	
    }
    
    public int get_of_cursor(bool delegate(string key, string value) prepare)
    {
    	throw new Exception ("not implemented");    	    
    }
    
    public long count_entries()
    {
    	throw new Exception ("not implemented");    	
    }
    
    public void reopen_db()
    {
    	throw new Exception ("not implemented");    	
    }
    
    public void close_db()
    {
    	throw new Exception ("not implemented");    	
    }
    
    public long dump_to_binlog()
    {
    	throw new Exception ("not implemented");    	
    }	

    public ResultCode remove(string in_key)
    {
    	throw new Exception ("not implemented");    	
    }	

}
