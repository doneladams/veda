/**
 * lmdb реализация хранилища
 */
module veda.core.storage.lmdb_storage;

private
{
    import std.stdio, std.file, std.datetime, std.conv, std.digest.ripemd, std.bigint, std.string, std.uuid, core.memory;
    import lmdb_header, individual, type;
    import logger, define;
}

/// Режим работы хранилища
enum DBMode
{
    /// чтение
    R  = true,

    /// чтение/запись
    RW = false
}

public bool[ string ] db_is_open;

/// key-value хранилище на lmdb
public class LmdbStorage
{
    MDB_env             *env;
    public const string summ_hash_this_db_id;
    private BigInt      summ_hash_this_db;
    protected DBMode    mode;
    private string      _path;
    string              db_name;
    string              parent_thread_name;
    long                last_op_id;
    long                committed_last_op_id;
    Logger              log;
    bool                db_is_opened;
    int                 max_count_record_in_memory = 10_000;
    byte[ string ]      records_in_memory;

    /// конструктор
    this(string _path_, DBMode _mode, string _parent_thread_name, Logger _log)
    {
        log                  = _log;
        _path                = _path_;
        db_name              = _path[ (lastIndexOf(path, '/') + 1)..$ ];
        summ_hash_this_db_id = "summ_hash_this_db";
        mode                 = _mode;
        parent_thread_name   = _parent_thread_name;

        string thread_name = "";
        if (thread_name is null || thread_name.length == 0)
        {
            //core_thread.getThis().name = "core" ~ text(randomUUID().toHash())[ 0..5 ];
        }

        //create_folder_struct();
        open_db();
//        reopen_db();
    }

    @property
    string path()
    {
        return this._path;
    }

  

    public void close_db()
    {
        //if (mode == DBMode.RW)
        //    flush(1);
        mdb_env_close(env);
        db_is_open[ _path ] = false;
        records_in_memory.clear;
        GC.collect();

//      writeln ("@@@ close_db, thread:", core.thread.Thread.getThis().name);
    }

    public void reopen_db()
    {
        if (mode == DBMode.R)
        {
            close_db();
            open_db();
            log.trace("reopen_db %s, mode=%s, thread:%s, last_op_id=%d", _path, text(mode), "", last_op_id);
        }
    }

    public void open_db()
    {
        //log.trace ("@@@ open_db #1 %s, mode=%s, thread:%s",  _path, text(mode), core.thread.Thread.getThis().name);

        if (db_is_open.get(_path, false) == true)
        {
            //log.trace("@@@ open_db #2 ", _path, ", thread:", core.thread.Thread.getThis().name, ", ALREADY OPENNING, db_is_open=", db_is_open);
            return;
        }

        int rc;

        rc = mdb_env_create(&env);
        if (rc != 0)
            log.trace_log_and_console("WARN! %s(%s) #1:%s", __FUNCTION__ ~ ":" ~ text(__LINE__), _path, fromStringz(mdb_strerror(rc)));
        else
        {
//            rc = mdb_env_open(env, cast(char *)_path, MDB_NOMETASYNC | MDB_NOSYNC | MDB_NOTLS, std.conv.octal !664);

            if (mode == DBMode.RW)
//              rc = mdb_env_open(env, cast(char *)_path, MDB_NOSYNC, std.conv.octal !664);
                rc = mdb_env_open(env, cast(char *)_path, MDB_NOMETASYNC | MDB_NOSYNC, std.conv.octal !664);
            else
                rc = mdb_env_open(env, cast(char *)_path, MDB_RDONLY | MDB_NOMETASYNC | MDB_NOSYNC | MDB_NOLOCK, std.conv.octal !666);


            if (rc != 0)
                log.trace_log_and_console("WARN! %s(%s) #2:%s", __FUNCTION__ ~ ":" ~ text(__LINE__), _path, fromStringz(mdb_strerror(rc)));
            else
                db_is_open[ _path ] = true;

            if (rc == 0)
            {
                string   data_str = find(false, null, summ_hash_this_db_id);

                string[] dataff = data_str.split(',');
                string   hash_str;
                if (dataff.length == 2)
                {
                    hash_str = dataff[ 0 ];

                    try
                    {
                        last_op_id           = to!long (dataff[ 1 ]);
                        committed_last_op_id = last_op_id;
                    }
                    catch (Throwable tr) {}
                }

                if (hash_str is null || hash_str.length < 1)
                    hash_str = "0";

                summ_hash_this_db = BigInt("0x" ~ hash_str);
                //log.trace("open db %s data_str=[%s], last_op_id=%d", _path, data_str, last_op_id);
                db_is_opened = true;
            }
        }
    }


    public string find(bool need_auth, string user_uri, string _uri, bool return_value = true)
    {
        string uri = _uri.idup;

        if (db_is_opened == false)
            open_db();

        if (uri is null || uri.length < 2)
            return null;

        if (db_is_open.get(_path, false) == false)
            return null;

        string  str = null;
        int     rc;
        MDB_txn *txn_r;
        MDB_dbi dbi;

        rc = mdb_txn_begin(env, null, MDB_RDONLY, &txn_r);
        if (rc == MDB_BAD_RSLOT)
        {
            for (int i = 0; i < 10 && rc != 0; i++)
            {
                //log.trace_log_and_console("[%s] warn: find:" ~ text(__LINE__) ~ "(%s) MDB_BAD_RSLOT", parent_thread_name, _path);
                mdb_txn_abort(txn_r);

                // TODO: sleep ?
                //if (i > 3)
                //    core_thread.sleep(dur!("msecs")(10));

                rc = mdb_txn_begin(env, null, MDB_RDONLY, &txn_r);
            }
        }

        if (rc != 0)
        {
            if (rc == MDB_MAP_RESIZED)
            {
                log.trace_log_and_console("WARN! " ~ __FUNCTION__ ~ ":" ~ text(__LINE__) ~ "(%s) %s", _path, fromStringz(mdb_strerror(rc)));
                reopen_db();
                return find(need_auth, user_uri, uri);
            }
            else if (rc == MDB_BAD_RSLOT)
            {
                log.trace_log_and_console("WARN! [%s] #2: find:" ~ text(__LINE__) ~ "(%s) MDB_BAD_RSLOT", parent_thread_name, _path);
                mdb_txn_abort(txn_r);

                // TODO: sleep ?
                //core.thread.Thread.sleep(dur!("msecs")(1));
                //rc = mdb_txn_begin(env, null, MDB_RDONLY, &txn_r);
                reopen_db();
                rc = mdb_txn_begin(env, null, MDB_RDONLY, &txn_r);
            }
        }

        if (rc != 0)
        {
            log.trace_log_and_console(__FUNCTION__ ~ ":" ~ text(__LINE__) ~ "(%s) ERR:%s", _path, fromStringz(mdb_strerror(rc)));
            return null;
        }

        try
        {
            rc = mdb_dbi_open(txn_r, null, 0, &dbi);
            if (rc != 0)
            {
                log.trace_log_and_console(__FUNCTION__ ~ ":" ~ text(__LINE__) ~ "(%s) ERR:%s", _path, fromStringz(mdb_strerror(rc)));
                return null;
            }

            MDB_val key;
            key.mv_size = uri.length;
            key.mv_data = cast(char *)uri;

            MDB_val data;
            rc = mdb_get(txn_r, dbi, &key, &data);
            if (rc == 0)
            {
                if (return_value)
                    str = cast(string)(data.mv_data[ 0..data.mv_size ]);
                else
                    str = "?";
            }
        }catch (Exception ex)
        {
            log.trace_log_and_console(__FUNCTION__ ~ ":" ~ text(__LINE__) ~ "(%s) ERR:%s", _path, ex.msg);
            return null;
        }

        scope (exit)
        {
            mdb_txn_abort(txn_r);
        }

        if (str !is null)
        {
            string res = str.dup;

            if (mode == DBMode.R)
            {
                records_in_memory[ uri ] = 1;

                if (records_in_memory.length > max_count_record_in_memory)
                {
                    log.trace("lmdb_storage: records_in_memory > max_count_record_in_memory (%d)", max_count_record_in_memory);
                    reopen_db();
                }
            }
            return res;
        }
        else
            return str;
    }
}
