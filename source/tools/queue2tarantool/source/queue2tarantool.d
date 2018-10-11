import std.stdio, core.stdc.stdlib, std.uuid;
import std.stdio, std.file, std.datetime.stopwatch, std.conv, std.digest.ripemd, std.bigint, std.string, std.uuid, core.memory;
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
long batch_size;
bool[ string ] opt;
double delta_to_print_count = 10000;

void main(string[] args)
{
    if (args.length < 5)
    {
        stderr.writeln("use queue2tarantool [start_pos] [delta] [batch_size] [opt]");
        return;
    }

    start_pos  = to!long (args[ 1 ]);
    delta      = to!long (args[ 2 ]);
    batch_size = to!long (args[ 3 ]);

    for (int idx = 4; idx < args.length; idx++)
    {
        string el = args[ idx ];
        opt[ el ] = true;
    }

    log.trace("start: %d, delta: %d, batch_size: %d, opt: %s", start_pos, delta, batch_size, opt);

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

    convert(individual_tt_storage, start_pos, delta, opt);
}


public long convert(KeyValueDB dest, long start_pos, long delta, bool[ string ] opt)
{
    long count;

    auto individual_queue = new Queue("./unload-queue", "individuals", Mode.R, log);

    individual_queue.open();

    auto new_id        = "cs_" ~ text(start_pos) ~ "_" ~ text(delta);
    auto individual_cs = new Consumer(individual_queue, "./", new_id ~ "", Mode.RW, log);
    individual_cs.open();

    long dcount = 0;
    count = individual_cs.count_popped;
	auto sw = StopWatch(AutoStart.no);

    while (true)
    {
        string data = individual_cs.pop();
        if (data is null)
            break;

        if (count % delta_to_print_count == 0)
        {
			long tt = sw.peek.total!"msecs";
			sw.reset ();
			
			auto cps = (delta_to_print_count/tt*1000);
            log.trace("count=%d, cps=%s", count, cps);            
        }

        count++;
        dcount++;

        // if (count == start_pos || dcount == delta)
        {
            dcount = 0;
            Individual indv;
            if (indv.deserialize(data) < 0)
            {
                log.trace("ERR! %d DATA=[%s]", count, data);
            }
            else
            {
                bool need_store = true;
                if (opt.get("check", false))
                {
                    Individual indv1;
                    
					sw.start();                    					
                    dest.get_individual(indv.uri, indv1);
                    sw.stop();
                    
                    if (indv1.getStatus() != ResultCode.OK)
                        need_store = true;
                    else
                        need_store = false;

                    if (opt.get("trace", false))
                    {
                        log.trace("TRACE, %d KEY=[%s] INDV+[%s]", individual_cs.count_popped, indv.uri, indv1);
                    }
                }

                if (need_store == true)
                {
                    string new_bin = indv.serialize();
                    dest.store(indv.uri, new_bin, -1);
                    log.trace("OK, %d KEY=[%s]", individual_cs.count_popped, indv.uri);
                }
            }
        }

        individual_cs.commit_and_next(true);

        if (count >= batch_size)
            break;
    }

    log.trace("count=%d", count);

    return count;
}

