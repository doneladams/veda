import std.stdio, std.socket, std.datetime, std.conv;
import individual;
import type, resource, veda.util.queue, veda.core.storage.lmdb_storage, logger, lmdb_header;


void main(string[] args)
{
    MDB_env    *env;
    MDB_txn    *txn;
    MDB_dbi    dbi;
    MDB_cursor *cursor;

    mdb_env_create(&env);

    mdb_env_set_maxdbs(env, 1);

    Logger       log = new Logger("lmdb_to_queue", "log", "");

    const string individual_queue_path = "./data/individuals";
    const string lmdb_db_path          = "./src-data/data/lmdb-individuals\0";

    log.tracec("open result %d", mdb_env_open(env, cast(const(char *))lmdb_db_path, 0, 777));

    log.tracec("txn begin %d", mdb_txn_begin(env, null, MDB_RDONLY, &txn));
    log.tracec("dbi open %d", mdb_dbi_open(txn, null, 0, &dbi));
    log.tracec("cursor open %d", mdb_cursor_open(txn, dbi, &cursor));

    Queue individuals_queue;

    individuals_queue = new Queue(individual_queue_path, "individuals-db", Mode.RW, log);

    individuals_queue.open();
    log.tracec("open queue [%s]", individuals_queue);

    long      count;

    StopWatch sw_total;
    StopWatch sw;

    sw.start;
    sw_total.start;

    if (individuals_queue.isReady)
    {
        try
        {
            int rc = 0;
            while (rc == 0)
            {
                MDB_val key, data;

                rc = mdb_cursor_get(cursor, &key, &data, MDB_cursor_op.MDB_NEXT);
                if (rc != 0)
                    break;
                string key_str  = cast(string)key.mv_data[ 0 .. key.mv_size ].dup;
                string data_str = cast(string)data.mv_data[ 0 .. data.mv_size ].dup;

                if (key_str == "summ_hash_this_db")
                    continue;

                Individual individual;
                string     new_state;

                if (key_str != "systicket")
                {
                    individual.deserialize(data_str);
                    new_state = individual.serialize_msgpack();
                }
                else
                {
                    Individual systicket;
                    systicket.uri = "systicket";
                    systicket.addResource("rdf:type", Resource(DataType.Uri, "ticket:Ticket"));
                    systicket.addResource("ticket:id", Resource(DataType.Uri, data_str));
                    new_state = systicket.serialize_msgpack();
                }

                Individual big_individual;
                big_individual.addResource("uri", Resource(DataType.Uri, "1"));
                big_individual.uri = text(count);
                big_individual.addResource("new_state", Resource(DataType.String, new_state));

                count++;

                if (count % 1000 == 0)
                {
                    sw.stop;
                    long t = cast(long)sw.peek().seconds;
                    sw.reset;
                    sw.start;
                    stderr.writefln("unload %d, batch %d seconds, total %d seconds", count, t, cast(long)sw_total.peek().seconds);
                }

                string bin = big_individual.serialize_msgpack();
                individuals_queue.push(bin);
            }
        }
        catch (Exception ex)
        {
            log.trace("ERR ex.msg=%s", ex.msg);
        }

        individuals_queue.close();
    }
}

