/**
 * core main thread
 */
module veda.core.srv.server;

private
{
    import core.stdc.stdlib, core.sys.posix.signal, core.sys.posix.unistd, core.runtime;
    import core.thread, std.stdio, std.string, core.stdc.string, std.outbuffer, std.datetime, std.conv, std.concurrency, std.process, std.json;
    import backtrace.backtrace, Backtrace = backtrace.backtrace;
    import veda.core.common.context, veda.core.common.know_predicates, veda.core.common.log_msg, veda.core.impl.thread_context;
    import veda.core.common.define, veda.common.type, veda.onto.individual, veda.onto.resource, veda.onto.bj8individual.individual8json;
    import veda.common.logger, veda.core.util.utils, veda.server.ticket;
    import veda.server.load_info, veda.server.tt_storage_manager, veda.server.nanomsg_channel;
}

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-server", "log", "server");
    return _log;
}
// ////// ////// ///////////////////////////////////////////

Logger io_msg;

enum CMD : byte
{
    /// Установить
    SET = 50,
}

static this()
{
    io_msg = new Logger("pacahon", "io", "server");
    bsd_signal(SIGINT, &handleTermination2);
}

bool f_listen_exit;

extern (C) void handleTermination2(int _signal)
{
    writefln("!SYS: %s: caught signal: %s", process_name, text(_signal));

    if (_log !is null)
        _log.trace("!SYS: %s: caught signal: %s", process_name, text(_signal));
    //_log.close();

    writeln("!SYS: ", process_name, ": preparation for the exit.");

    f_listen_exit = true;

    thread_term();
    Runtime.terminate();
}

Context l_context;

void main(char[][] args)
{
    Tid[ P_MODULE ] tids;
    process_name = "server";
    string node_id = null;

    create_folder_struct();

    tids[ P_MODULE.subject_manager ] = spawn(&tt_individuals_manager, P_MODULE.subject_manager, individuals_db_path, node_id);
    if (wait_starting_thread(P_MODULE.subject_manager, tids) == false)
        return;

    //tids[ P_MODULE.ticket_manager ] = spawn(&individuals_manager, P_MODULE.ticket_manager, tickets_db_path, node_id);
    //wait_starting_thread(P_MODULE.ticket_manager, tids);

    //tids[ P_MODULE.acl_preparer ] = spawn(&acl_manager, text(P_MODULE.acl_preparer), acl_indexes_db_path);
    //wait_starting_thread(P_MODULE.acl_preparer, tids);

    tids[ P_MODULE.commiter ] =
        spawn(&commiter, text(P_MODULE.commiter));
    wait_starting_thread(P_MODULE.commiter, tids);

    tids[ P_MODULE.statistic_data_accumulator ] = spawn(&statistic_data_accumulator, text(P_MODULE.statistic_data_accumulator));
    wait_starting_thread(P_MODULE.statistic_data_accumulator, tids);

    foreach (key, value; tids)
    {
        register(text(key), value);
    }

    Ticket ticket = create_new_ticket("cfg:VedaSystem", "90000000", null);

    long   op_id;
    // put(P_MODULE storage_id, bool need_auth, string user_uri, Resources type, string indv_uri, string prev_state, string new_state, long update_counter,
    //   string event_id, long transaction_id, bool ignore_freeze, out long op_id)
    // ticket_storage_module.put(P_MODULE.ticket_manager, false, null, Resources.init, "systicket", null, ticket.id, -1, null, -1, false, op_id);

    Individual new_ticket;
    new_ticket.uri = ticket.id;
    Resources  type = [ Resource(ticket__Ticket) ];
    new_ticket.resources[ rdf__type ] = type;
    new_ticket.resources[ ticket__accessor ] ~= Resource(ticket.user_uri);
    new_ticket.resources[ ticket__when ] ~= Resource(getNowAsString());
    new_ticket.resources[ ticket__duration ] ~= Resource("90000000");
    subject_storage_module.put(P_MODULE.subject_manager, false, "cfg:VedaSystem", type,
                               ticket.id, null, new_ticket.serialize(), -1, null, -1, false, op_id);

    Individual systicket;
    systicket.uri                    = "systicket";
    type                             = [ Resource(ticket__Ticket) ];
    systicket.resources[ rdf__type ] = type;
    systicket.resources[ "ticket:id" ] ~= Resource(ticket.id);

    subject_storage_module.put(P_MODULE.subject_manager, false, "cfg:VedaSystem", Resources.init,
                               "systicket", null, systicket.serialize(), -1, null, -1, false, op_id);
    log.trace("systicket [%s] was created", ticket.id);
    log.trace("CREATE SYSTICKET...OK");

    tids[ P_MODULE.n_channel ] = spawn(&nanomsg_channel, text(P_MODULE.n_channel));
    wait_starting_thread(P_MODULE.n_channel, tids);

    tids[ P_MODULE.print_statistic ] = spawn(&print_statistic, text(P_MODULE.print_statistic),
                                             tids[ P_MODULE.statistic_data_accumulator ]);
    wait_starting_thread(P_MODULE.print_statistic, tids);

    foreach (key, value; tids)
    {
        register(text(key), value);
    }

    while (f_listen_exit == false)
        core.thread.Thread.sleep(dur!("seconds")(1000));

    writefln("send signals EXIT to threads");

    exit(P_MODULE.commiter);
    //exit(P_MODULE.acl_preparer);
    exit(P_MODULE.subject_manager);
    //exit(P_MODULE.ticket_manager);

    thread_term();
}

bool wait_starting_thread(P_MODULE tid_idx, ref Tid[ P_MODULE ] tids)
{
    bool res;
    Tid  tid = tids[ tid_idx ];

    if (tid == Tid.init)
        throw new Exception("wait_starting_thread: Tid=" ~ text(tid_idx) ~ " not found", __FILE__, __LINE__);

    log.trace("START THREAD... : %s", text(tid_idx));
    send(tid, thisTid);
    receive((bool isReady)
            {
                res = isReady;
                //if (trace_msg[ 50 ] == 1)
                log.trace("START THREAD IS SUCCESS: %s", text(tid_idx));
                if (res == false)
                    log.trace("FAIL START THREAD: %s", text(tid_idx));
            });
    return res;
}

public void exit(P_MODULE module_id)
{
    Tid tid_module = getTid(module_id);

    if (tid_module != Tid.init)
    {
        writefln("send command EXIT to thread_%s", text(module_id));
        send(tid_module, CMD_EXIT, thisTid);
        receive((bool _res) {});
    }
}

void commiter(string thread_name)
{
    core.thread.Thread.getThis().name = thread_name;
    // SEND ready
    receive((Tid tid_response_reciever)
            {
                send(tid_response_reciever, true);
            });

    bool is_exit = false;

    while (is_exit == false)
    {
        receiveTimeout(dur!("seconds")(1),
                       (byte cmd, Tid tid_response_reciever)
                       {
                           if (cmd == CMD_EXIT)
                           {
                               is_exit = true;
                               writefln("[%s] recieve signal EXIT", "commiter");
                               send(tid_response_reciever, true);
                           }
                       },
                       (OwnerTerminated ot)
                       {
                           return;
                       },
                       (Variant v) { writeln(thread_name, "::commiter::Received some other type.", v); });

        //veda.server.storage_manager.flush_int_module(P_MODULE.subject_manager, false);
        //veda.server.acl_manager.flush(false);
        //veda.server.storage_manager.flush_int_module(P_MODULE.ticket_manager, false);
    }
}
