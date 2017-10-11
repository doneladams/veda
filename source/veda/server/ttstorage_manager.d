/**
 * процесс отвечающий за хранение
 */
module veda.server.tt_storage_manager;

private
{
    import core.thread, std.stdio, std.conv, std.concurrency, std.file, std.datetime, std.outbuffer, std.string;
    import veda.common.logger, veda.core.util.utils, veda.util.queue;
    import veda.core.common.context, veda.core.common.define, veda.core.common.log_msg, veda.onto.individual, veda.onto.resource;
    import veda.core.storage.binlog_tools, veda.util.module_info;
    import veda.core.search.vel, veda.common.type;
    import kaleidic.nanomsg.nano;
    import msgpack;
    import veda.connector.connector;
    import veda.connector.requestresponse;
}

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-server", "log", "TT-STORAGE-MNGR");
    return _log;
}

struct TransactionItem
{
    byte       cmd;
    string     indv_serl;
    string     ticket_id;
    string     event_id;

    Individual indv;

    this(byte _cmd, string _indv_serl, string _ticket_id, string _event_id)
    {
        cmd       = _cmd;
        indv_serl = _indv_serl;
        ticket_id = _ticket_id;
        event_id  = _event_id;

        int code = indv.deserialize(indv_serl);
        if (code < 0)
        {
            log.trace("ERR:v8d:transaction:deserialize [%s]", indv_serl);
        }
    }
}
TransactionItem *[ string ] transaction_buff;
TransactionItem *[] transaction_queue;
private string tarantool_addr = "127.0.0.1";
private ushort tarantool_port = 9999;

public void freeze(P_MODULE storage_id)
{
    writeln("FREEZE");
    Tid tid_subject_manager = getTid(storage_id);

    if (tid_subject_manager != Tid.init)
    {
        send(tid_subject_manager, CMD_FREEZE, thisTid);
        receive((bool _res) {});
    }
}

public void unfreeze(P_MODULE storage_id)
{
    writeln("UNFREEZE");
    Tid tid_subject_manager = getTid(storage_id);

    if (tid_subject_manager != Tid.init)
    {
        send(tid_subject_manager, CMD_UNFREEZE);
    }
}

public string find(P_MODULE storage_id, string uri)
{
    string res;
    Tid    tid_subject_manager = getTid(P_MODULE.subject_manager);

    if (tid_subject_manager !is Tid.init)
    {
        send(tid_subject_manager, CMD_FIND, uri, thisTid);
        receive((string key, string data, Tid tid)
                {
                    res = data;
                });
    }
    else
        throw new Exception("find [" ~ uri ~ "], !!! NOT FOUND TID=" ~ text(P_MODULE.subject_manager));

    return res;
}

public long unload(P_MODULE storage_id, string queue_name, bool only_ids)
{
    Tid  tid   = getTid(storage_id);
    long count = -1;

    if (tid != Tid.init)
    {
        send(tid, CMD_UNLOAD, queue_name, only_ids, thisTid);
        receive((long _count) { count = _count; });
    }
    return count;
}

public string backup(P_MODULE storage_id)
{
    string backup_id;

    Tid    tid_subject_manager = getTid(storage_id);

    send(tid_subject_manager, CMD_BACKUP, "", thisTid);
    receive((string res) { backup_id = res; });

    return backup_id;
}

public ResultCode msg_to_module(P_MODULE f_module, string msg, bool is_wait)
{
    ResultCode rc;

    Tid        tid = getTid(P_MODULE.subject_manager);

    if (tid != Tid.init)
    {
        if (is_wait == false)
        {
            send(tid, CMD_MSG, f_module, msg);
        }
        else
        {
            send(tid, CMD_MSG, msg, f_module, thisTid);
            receive((bool isReady) {});
        }
        rc = ResultCode.OK;
    }
    return rc;
}

public ResultCode flush_int_module(P_MODULE f_module, bool is_wait)
{
    ResultCode rc;
    Tid        tid = getTid(f_module);

    if (tid != Tid.init)
    {
        if (is_wait == false)
        {
            send(tid, CMD_COMMIT);
        }
        else
        {
            send(tid, CMD_COMMIT, thisTid);
            receive((bool isReady) {});
        }
        rc = ResultCode.OK;
    }
    return rc;
}

public void flush_ext_module(P_MODULE f_module, long wait_op_id)
{
    Tid tid = getTid(P_MODULE.subject_manager);

    if (tid != Tid.init)
    {
        send(tid, CMD_COMMIT, f_module, wait_op_id);
    }
}

public long unload(P_MODULE storage_id, string queue_name)
{
    Tid  tid   = getTid(storage_id);
    long count = -1;

    if (tid != Tid.init)
    {
        send(tid, CMD_UNLOAD, queue_name, thisTid);
        receive((long _count) { count = _count; });
    }
    return count;
}

public ResultCode put(P_MODULE storage_id, OptAuthorize op_auth, string user_uri, Resources type, string indv_uri, string prev_state, string new_state,
                      long update_counter,
                      string event_id, long transaction_id, bool ignore_freeze,
                      out long op_id)
{
    ResultCode rc;
    Tid        tid = getTid(storage_id);

    if (tid != Tid.init)
    {
        send(tid, INDV_OP.PUT, op_auth, user_uri, indv_uri, prev_state, new_state, update_counter, event_id, transaction_id, ignore_freeze, thisTid);

        receive((ResultCode _rc, Tid from)
                {
                    if (from == getTid(storage_id))
                        rc = _rc;
                    op_id = get_subject_manager_op_id();
                    return true;
                });
    }
    return rc;
}

public ResultCode remove(P_MODULE storage_id, OptAuthorize op_auth, string user_uri, string uri, long transaction_id, bool ignore_freeze, out long op_id)
{
    ResultCode rc;
    Tid        tid = getTid(storage_id);

    if (tid != Tid.init)
    {
        send(tid, INDV_OP.REMOVE, user_uri, uri, transaction_id, ignore_freeze, thisTid);

        receive((ResultCode _rc, Tid from)
                {
                    if (from == getTid(storage_id))
                        rc = _rc;
                    op_id = get_subject_manager_op_id();
                    return true;
                });
    }
    return rc;
}

public void tt_individuals_manager(P_MODULE _storage_id, string db_path, string node_id)
{
    Queue                        individual_queue;
    Queue                        uris_queue;

    P_MODULE                     storage_id  = _storage_id;
    string                       thread_name = text(storage_id);

    core.thread.Thread.getThis().name = thread_name;

    int                          size_bin_log     = 0;
    int                          max_size_bin_log = 10_000_000;
    string                       bin_log_name; //         = get_new_binlog_name(db_path);
    long                         last_reopen_rw_op_id = 0;

    long                         op_id = 0;

    string                       notify_channel_url = "tcp://127.0.0.1:9111\0";
    int                          sock;
    bool                         already_notify_channel = false;
    ModuleInfoFile               module_info;

    Connector                    connector = new Connector(log);

    try
    {
        if (storage_id == P_MODULE.subject_manager)
        {
            individual_queue = new Queue(queue_db_path, "individuals-flow", Mode.RW, log);
            log.trace("open queue [%s]", individual_queue);
            individual_queue.open();

            uris_queue = new Queue(uris_db_path, "uris-db", Mode.RW, log);
            log.trace("open queue [%s]", uris_queue);
            uris_queue.open();

            sock = nn_socket(AF_SP, NN_PUB);
            if (sock >= 0)
            {
                if (nn_bind(sock, cast(char *)notify_channel_url) >= 0)
                {
                    already_notify_channel = true;
                }
            }
        }

        string last_backup_id = "---";

        bool   is_freeze = false;
        bool   is_exit   = false;
        module_info = new ModuleInfoFile(text(storage_id), _log, OPEN_MODE.WRITER);

        if (!module_info.is_ready)
        {
            writefln("thread [%s] terminated", process_name);
            // SEND ready
            receive((Tid tid_response_reciever)
                    {
                        send(tid_response_reciever, false);
                    });
            core.thread.Thread.sleep(dur!("seconds")(1));

            return;
        }

        // SEND ready
        receive((Tid tid_response_reciever)
                {
                    send(tid_response_reciever, true);
                });

        connector.connect(tarantool_addr, tarantool_port);

        while (is_exit == false)
        {
            try
            {
                receive(
                        (byte cmd, P_MODULE f_module, string _msg)
                        {
                            if (cmd == CMD_MSG)
                            {
                                string msg = "MSG:" ~ text(f_module) ~ ":" ~ _msg;
                                int bytes = nn_send(sock, cast(char *)msg, msg.length + 1, 0);
                                log.trace("SEND %d bytes [%s] TO %s", bytes, msg, notify_channel_url);
                            }
                        },
                        (byte cmd, P_MODULE f_module, long wait_op_id)
                        {
                            if (cmd == CMD_COMMIT)
                            {
                                string msg = "MSG:" ~ text(f_module) ~ ":COMMIT";
                                int bytes = nn_send(sock, cast(char *)msg, msg.length + 1, 0);
                                log.trace("SEND %d bytes [%s] TO %s, wait_op_id=%d", bytes, msg, notify_channel_url, wait_op_id);
                            }
                        },
                        (byte cmd)
                        {
                            if (cmd == CMD_UNFREEZE)
                            {
                                log.trace("UNFREEZE");
                                is_freeze = false;
                            }
                        },
                        (byte cmd, Tid tid_response_reciever)
                        {
                            if (cmd == CMD_FREEZE)
                            {
                                log.trace("FREEZE");
                                is_freeze = true;
                                send(tid_response_reciever, true);
                            }
                            else if (cmd == CMD_EXIT)
                            {
                                is_exit = true;
                                writefln("[%s] recieve signal EXIT", text(storage_id));
                                send(tid_response_reciever, true);
                            }

                            else if (cmd == CMD_NOP)
                                send(tid_response_reciever, true);
                            else
                                send(tid_response_reciever, false);
                        },
                        (byte cmd, string key, string msg)
                        {
                            if (cmd == CMD_PUT_KEY2SLOT)
                            {
                                log.trace("ERR! CMD_PUT_KEY2SLOT storage.put(key, msg, -1) not implemented ");
                                //storage.put(key, msg, -1);
                            }
                        },
                        (byte cmd, string arg, Tid tid_response_reciever)
                        {
/*							if (cmd == CMD_UNLOAD)
                            {
                                long count;
                                Queue queue = new Queue(arg, Mode.RW, log);

                                if (queue.open(Mode.RW))
                                {
                                    bool add_to_queue(string key, string value)
                                    {
                                        queue.push(value);
                                        count++;
                                        return true;
                                    }

                                    storage.get_of_cursor(&add_to_queue);
                                    queue.close();
                                }
                                else
                                    writeln("store_thread:CMD_UNLOAD: not open queue");

                                send(tid_response_reciever, count);
                            }*/
                        },
                        (INDV_OP cmd, string user_uri, string uri, long transaction_id, bool ignore_freeze, Tid tid_response_reciever)
                        {
                            ResultCode rc = ResultCode.Not_Ready;

                            if (!ignore_freeze && is_freeze && cmd == INDV_OP.REMOVE)
                                send(tid_response_reciever, rc, thisTid);

                            try
                            {
                                if (cmd == INDV_OP.REMOVE)
                                {
                                    stderr.writefln("@TRY REMOVE %s", uri);
                                    RequestResponse request_response = connector.remove(OptAuthorize.NO, user_uri, [ uri ], false);
                                    if (request_response.common_rc != ResultCode.OK)
                                        stderr.writeln("@ERR COMMON REMOVE! ", request_response.common_rc);
                                    else if (request_response.op_rc[ 0 ] != ResultCode.OK)
                                        stderr.writeln("@ERR REMOVE! ", request_response.op_rc[ 0 ]);

                                    send(tid_response_reciever, request_response.common_rc, thisTid);

                                    return;
                                }
                            }
                            catch (Exception ex)
                            {
                                send(tid_response_reciever, ResultCode.Fail_Commit, thisTid);
                                return;
                            }
                        },
                        (INDV_OP cmd, OptAuthorize op_auth, string user_uri, string indv_uri, string prev_state, string new_state, long update_counter, string event_id,
                         long transaction_id, bool ignore_freeze, Tid tid_response_reciever)
                        {
                            ResultCode rc = ResultCode.Not_Ready;

                            if (!ignore_freeze && is_freeze && cmd == INDV_OP.PUT)
                                send(tid_response_reciever, rc, thisTid);

                            try
                            {
                                if (cmd == INDV_OP.PUT)
                                {
                                    if (storage_id == P_MODULE.subject_manager)
                                    {
								        if (user_uri is null || user_uri.length == 0)
								            user_uri = "cfg:Guest";
                                    	
                                        Individual imm;
                                        imm.uri = text(op_id);
                                        imm.addResource("cmd", Resource(cmd));
                                        imm.addResource("uri", Resource(DataType.Uri, indv_uri));

                                        if (user_uri !is null && user_uri.length > 0)
                                            imm.addResource("user_uri", Resource(DataType.Uri, user_uri));

                                        imm.addResource("new_state", Resource(DataType.String, new_state));

                                        if (prev_state !is null && prev_state.length > 0)
                                            imm.addResource("prev_state", Resource(DataType.String, prev_state));
                                        else
                                            uris_queue.push(indv_uri);

                                        if (event_id !is null && event_id.length > 0)
                                            imm.addResource("event_id", Resource(DataType.String, event_id));

                                        if (transaction_id >= 0)
                                            imm.addResource("tnx_id", Resource(DataType.String, text(transaction_id)));

                                        imm.addResource("op_id", Resource(op_id));
                                        imm.addResource("u_count", Resource(update_counter));

                                        //log.trace("SEND TO TT %s ", imm);

                                        string binobj = imm.serialize();

                                        RequestResponse request_response = connector.put(op_auth, user_uri, [ binobj ]);

                                        set_subject_manager_op_id(op_id);
                                        op_id++;

                                        if (request_response.common_rc != ResultCode.OK)
                                        {
                                            rc = request_response.common_rc;
                                            send(tid_response_reciever, rc, thisTid);

                                            log.trace("ERR!, ttstorage_manager: PUT, op_auth=%s, res=%s, %s", op_auth, rc, imm);
                                        }
                                        else if (request_response.op_rc[ 0 ] != ResultCode.OK)
                                        {
                                            rc = request_response.op_rc[ 0 ];
                                            send(tid_response_reciever, rc, thisTid);

                                            log.trace("ERR!, ttstorage_manager: PUT, op_auth=%s, res=%s, %s", op_auth, rc, imm);
                                        }
                                        else
                                        {
                                            rc = request_response.op_rc[ 0 ];
                                            //    stderr.writeln("@OK");

                                            individual_queue.push(binobj);
//                                          string msg_to_modules = indv_uri ~ ";" ~ text(update_counter) ~ ";" ~ text (op_id) ~ "\0";
                                            string msg_to_modules = format("#%s;%d;%d", indv_uri, update_counter, op_id);

                                            int bytes = nn_send(sock, cast(char *)msg_to_modules, msg_to_modules.length, 0);
//                                          log.trace("SEND %d bytes UPDATE SIGNAL TO %s", bytes, notify_channel_url);

                                            //Tid tid_ccus_channel = getTid(P_MODULE.ccus_channel);
                                            //if (tid_ccus_channel !is Tid.init)
                                            //{
                                            //    //log.trace("SEND SIGNAL TO CCUS %s", msg_to_modules);
                                            //    send(tid_ccus_channel, msg_to_modules);
                                            //}

                                            send(tid_response_reciever, rc, thisTid);

                                            module_info.put_info(op_id, op_id);
                                            string new_hash = "0000";
                                            bin_log_name = write_in_binlog(new_state, new_hash, bin_log_name, size_bin_log, max_size_bin_log, db_path);
                                        }
                                    }

                                    return;
                                }
                            }
                            catch (Exception ex)
                            {
                                send(tid_response_reciever, ResultCode.Fail_Commit, thisTid);
                                return;
                            }

/*
                        if (cmd == CMD_BACKUP)
                        {
                            try
                            {
                                string backup_id;
                                if (msg.length > 0)
                                    backup_id = msg;
                                else
                                    backup_id = storage.find(storage.summ_hash_this_db_id);

                                if (backup_id is null)
                                    backup_id = "0";

                                if (last_backup_id != backup_id)
                                {
                                    Result res = storage.backup(backup_id);
                                    if (res == Result.Ok)
                                    {
                                        size_bin_log = 0;
                                        bin_log_name = get_new_binlog_name(db_path);
                                        last_backup_id = backup_id;
                                    }
                                    else if (res == Result.Err)
                                    {
                                        backup_id = "";
                                    }
                                }
                                send(tid_response_reciever, backup_id);
                            }
                            catch (Exception ex)
                            {
                                send(tid_response_reciever, "");
                            }
                        }

                        else
                        {
                            send(tid_response_reciever, msg, "err in individuals_manager", thisTid);
                        }
 */
                        },
                        (byte cmd, int arg, bool arg2)
                        {
                            if (cmd == CMD_SET_TRACE)
                                set_trace(arg, arg2);
                        },
                        (OwnerTerminated ot)
                        {
                            //log.trace("%s::storage_manager::OWNER TERMINATED", thread_name);
                            return;
                        },
                        (Variant v) { log.trace("%s::storage_manager::Received some other type. %s", thread_name, v); });
            }
            catch (Throwable ex)
            {
                log.trace("individuals_manager# ERR! LINE:[%s], FILE:[%s], MSG:[%s]", ex.line, ex.file, ex.msg);
            }
        }
    } finally
    {
        connector.close();

        if (module_info !is null)
        {
            module_info.close();
            module_info = null;
        }

        if (individual_queue !is null)
        {
            individual_queue.close();
            individual_queue = null;
        }

        if (uris_queue !is null)
        {
            uris_queue.close();
            uris_queue = null;
        }
    }
}

unittest
{
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

    import veda.core.impl.thread_context;
    import std.datetime;
    import veda.onto.lang;
    import veda.util.tests_tools;

    string test_path = get_test_path();
    string db_path   = test_path ~ "/lmdb-individuals";

    Tid[ P_MODULE ] tids;

    try
    {
        mkdir(db_path);
    }
    catch (Exception ex)
    {
    }

    tids[ P_MODULE.subject_manager ] = spawn(&individuals_manager, P_MODULE.subject_manager, db_path, "?");

    assert(wait_starting_thread(P_MODULE.subject_manager, tids));

    foreach (key, value; tids)
        register(text(key), value);

    Logger     log = new Logger("test", "log", "storage-manager");

    Context    ctx = new PThreadContext("", "test", db_path, log, "");

    Individual new_indv_A = generate_new_test_individual();

    Ticket     ticket;

    OpResult   oprs = ctx.put_individual(&ticket, new_indv_A.uri, new_indv_A, false, "", true, false);

    assert(oprs.result == ResultCode.OK, "OpResult=" ~ text(oprs));

    string binobj = ctx.get_from_individual_storage(new_indv_A.uri);

    assert(binobj !is null);
    assert(binobj.length > 3);

    Individual indv_B;
    indv_B.deserialize(binobj);

    bool compare_res = new_indv_A.compare(indv_B);
    if (compare_res == false)
        writefln("new_indv_A [%s] != indv_B [%s]", new_indv_A, indv_B);

    assert(compare_res);

    writeln("unittest [Storage module] Ok");
}
