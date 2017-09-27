import std.stdio, std.socket, std.datetime, std.conv;
import individual;
import connector, type, resource, requestresponse, veda.util.queue, veda.core.storage.lmdb_storage, logger;

void main(string[] args)
{
    Connector connector = new Connector();

    connector.connect("127.0.0.1", 9999);

    Logger       log = new Logger("lmdb_to_tarantool", "log", "");

    const string uris_db_path = "./src-data/data/uris";
    const string lmdb_db_path = "./src-data/data/lmdb-individuals";

    Queue        uris_queue;
    Consumer     uris_queue_cs;

    uris_queue = new Queue(uris_db_path, "uris-db", Mode.R, log);
    stderr.writefln("open queue [%s]", uris_queue);
    uris_queue.open();

    if (uris_queue.isReady)
    {
        uris_queue_cs = new Consumer(uris_queue, uris_db_path, "to_tarantool", Mode.RW, log);
        if (!uris_queue_cs.open())
        {
            log.trace("not found uncompleted job, start new read queue");
        }
        else
            log.trace("found uncompleted job");

        LmdbStorage inividuals_storage_r;
        inividuals_storage_r = new LmdbStorage(lmdb_db_path, DBMode.R, "inividuals", log);

        inividuals_storage_r.open_db();


        long      count;

        StopWatch sw_total;
        StopWatch sw;

        sw.start;
        sw_total.start;

        try
        {
            string data;

            if (uris_queue_cs !is null)
            {
                while (true)
                {
                    data = uris_queue_cs.pop();
                    if (data is null)
                    {
                        stderr.writefln("queue is empty");
                        break;
                    }

                    //stderr.writefln("uri=%s", data);

                    string data_str = inividuals_storage_r.find(false, null, data, true);
                    string key_str  = data;

                    if (key_str == "summ_hash_this_db")
                    {
                        uris_queue_cs.commit_and_next(true);
                        continue;
                    }

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

                    Individual tt_put_packet;
                    tt_put_packet.addResource("uri", Resource(DataType.Uri, "1"));
                    tt_put_packet.uri = "1";
                    tt_put_packet.addResource("new_state", Resource(DataType.String, new_state));

                    count++;

                    if (count % 1000 == 0)
                    {
                        sw.stop;
                        long t = cast(long)sw.peek().seconds;
                        sw.reset;
                        sw.start;
                        stderr.writefln("send to tarantool %d, batch %d seconds, total %d seconds", count, t, cast(long)sw_total.peek().seconds);
                    }

                    string          bin = tt_put_packet.serialize_msgpack();
                    RequestResponse rr  = connector.put(false, "cfg:VedaSystem", [ bin ]);
                    if (rr.common_rc != ResultCode.OK)
                    {
                        stderr.writefln("@COMMON ERR WITH CODE %d", rr.common_rc);
                        stderr.writeln(new_state);
                        uris_queue_cs.commit_and_next(true);
                        continue;
                    }
                    else if (rr.op_rc[ 0 ] != ResultCode.OK)
                    {
                        stderr.writefln("@OP ERR WITH CODE %d", rr.common_rc);
                        stderr.writeln(new_state);
                        uris_queue_cs.commit_and_next(true);
                        continue;
                    }

                    uris_queue_cs.commit_and_next(true);
                }
            }
        }
        catch (Exception ex)
        {
            //printPrettyTrace(stderr);
            stderr.writefln("@ERR %s", ex.msg);

            if (uris_queue !is null)
            {
                uris_queue.close();
                uris_queue = null;
            }
        }
    }
}
