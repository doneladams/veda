import std.stdio, core.stdc.stdlib, std.uuid;
import std.stdio, std.file, std.datetime, std.conv, std.digest.ripemd, std.bigint, std.string, std.uuid, core.memory;
alias core.thread.Thread core_thread;
import veda.core.common.define;
import veda.storage.tarantool.tarantool_driver, veda.storage.common, veda.common.type, veda.onto.individual;
import veda.util.properd, veda.util.queue;
import veda.common.logger;

Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("convert_" ~ text(start_pos) ~ "_" ~ text(delta), "log", "");
    return _log;
}

long start_pos;
long delta;

void main(string[] args)
{
    if (args.length < 3)
    {
        stderr.writeln("use queue2tarantool start_pos delta");
        return;
    }

    start_pos = to!long (args[ 1 ]);
    delta     = to!long (args[ 2 ]);

    log.trace("start: %d, delta: %d", start_pos, delta);

    KeyValueDB individual_tt_storage;
    KeyValueDB ticket_tt_storage;

    string[ string ] properties;
    properties = readProperties("./veda.properties");
    string tarantool_url = properties.as!(string)("tarantool_url");

    log.trace("connect to tarantool");
    if (tarantool_url !is null)
    {
        individual_tt_storage = new TarantoolDriver(log, "INDIVIDUALS", 512);
        ticket_tt_storage     = new TarantoolDriver(log, "TICKETS", 513);
    }

    convert(individual_tt_storage, start_pos, delta);
}


public long convert(KeyValueDB dest, long start_pos, long delta)
{
    long count;

    auto individual_queue = new Queue("./unload-queue", "individuals", Mode.R, log);

    individual_queue.open();

    auto new_id        = randomUUID().toString();
    auto individual_cs = new Consumer(individual_queue, "./", new_id ~ "", Mode.RW, log);
    individual_cs.open();


    long dcount = 0;

    while (true)
    {
        string data = individual_cs.pop();
        if (data is null)
            break;

        if (count % 10000 == 0)
            log.trace("count=%d", count);

        count++;
        dcount++;

        if (count == start_pos || dcount == delta)
        {
            dcount = 0;
            Individual indv;
            if (indv.deserialize(data) < 0)
            {
                log.trace("ERR! %d DATA=[%s]", count, data);
            }
            else
            {
                string new_bin = indv.serialize();
                dest.store(indv.uri, new_bin, -1);
                log.trace("OK, %d KEY=[%s]", count, indv.uri);
            }
        }
        individual_cs.commit_and_next(true);
    }

    return count;
}

