import std.stdio;
import veda.storage.mdbx.mdbx_driver, veda.storage.common, veda.common.type;
import veda.util.properd;
import veda.common.logger;

Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("az-lmdb-dump-2-mdbx", "log", "");
    return _log;
}

const string acl_indexes_db_path = "./data/acl-indexes";

void main(string[] args)
{
    KeyValueDB storage;

    storage =  new MdbxDriver(acl_indexes_db_path, DBMode.RW, "", log);

    string file_name = args[ 1 ];
    writefln("read file [%s]", file_name);
    auto   file = File(file_name, "r");

    bool   is_prepare = false;
    string line;

    long counter = 0;

    while ((line = file.readln()) !is null)
    {
        if (line == " summ_hash_this_db\n")
            is_prepare = false;
        if (is_prepare)
        {
	    counter++;
            string key   = line;
            string value = file.readln();
            
            key = key[ 1..$ - 1 ];
            value = value[ 1..$ - 1 ];
            
            writefln("%d KEY=[%s]", counter, key);
            //writefln("VALUE=[%s]", value);
            
            storage.put (OptAuthorize.NO, null, key, value, -1);
        }
        if (line == "HEADER=END\n")
            is_prepare = true;
    }
    writefln ("FLUSH");

    storage.close();

    writefln ("FINISH");
}
