/**
 * master storage
 */
module veda.mstorage.server;

private
{
    import core.stdc.stdlib, core.sys.posix.signal, core.sys.posix.unistd, core.runtime;
    import core.thread, std.stdio, std.string, core.stdc.string, std.outbuffer, std.datetime, std.conv, std.concurrency, std.process, std.json,
           std.regex, std.uuid, std.random;
    import veda.util.properd;
    import veda.core.common.context, veda.core.common.know_predicates, veda.core.common.log_msg, veda.core.impl.thread_context, veda.core.search.vql;
    import veda.core.common.define, veda.common.type, veda.onto.individual, veda.onto.resource, veda.onto.bj8individual.individual8json;
    import veda.common.logger, veda.core.util.utils, veda.core.common.transaction;
    import veda.mstorage.acl_manager, veda.storage.storage_manager, veda.mstorage.nanomsg_channel, veda.storage.storage;
    import veda.storage.common, veda.authorization.authorization;
    import veda.onto.individual;
}

alias veda.storage.storage_manager ticket_storage_module;
alias veda.storage.storage_manager indv_storage_thread;
alias veda.mstorage.acl_manager    acl_module;

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-mstorage", "log", "mstorage");
    return _log;
}
// ////// ////// ///////////////////////////////////////////

bool   f_listen_exit = false;
Logger io_msg;

static this()
{
    io_msg = new Logger("pacahon", "io", "mstorage");
    bsd_signal(SIGINT, &handleTermination2);
}

extern (C) void handleTermination2(int _signal)
{
    writefln("!SYS: %s: caught signal: %s", process_name, text(_signal));

    if (_log !is null)
        _log.trace("!SYS: %s: caught signal: %s", process_name, text(_signal));
    //_log.close();

    writeln("!SYS: ", process_name, ": preparation for the exit.");

    f_listen_exit = true;

    //thread_term();
    Runtime.terminate();
}

private Context l_context;

void main(char[][] args)
{
    Tid[ P_MODULE ] tids;
    process_name = "mstorage";
    string node_id = null;

    tids[ P_MODULE.subject_manager ] = spawn(&individuals_manager, P_MODULE.subject_manager, node_id);
    if (wait_starting_thread(P_MODULE.subject_manager, tids) == false)
        return;

    tids[ P_MODULE.ticket_manager ] = spawn(&individuals_manager, P_MODULE.ticket_manager, node_id);
    wait_starting_thread(P_MODULE.ticket_manager, tids);

    tids[ P_MODULE.acl_preparer ] = spawn(&acl_manager, text(P_MODULE.acl_preparer));
    wait_starting_thread(P_MODULE.acl_preparer, tids);

    tids[ P_MODULE.commiter ] =
        spawn(&commiter, text(P_MODULE.commiter));
    wait_starting_thread(P_MODULE.commiter, tids);

    tids[ P_MODULE.n_channel ] = spawn(&nanomsg_channel, text(P_MODULE.n_channel));
    wait_starting_thread(P_MODULE.n_channel, tids);

    foreach (key, value; tids)
        register(text(key), value);

    init(null);

    while (f_listen_exit == false)
        core.thread.Thread.sleep(dur!("seconds")(1000));

    writefln("send signals EXIT to threads");

    exit(P_MODULE.commiter);
    exit(P_MODULE.acl_preparer);
    exit(P_MODULE.subject_manager);
    exit(P_MODULE.ticket_manager);

    //thread_term();
}

void init(string node_id)
{
    Context core_context;
    Ticket  sticket;

    if (node_id is null || node_id.length < 2)
        node_id = "cfg:standart_node";

    log.trace("init_core: node_id=[%s]", node_id);

    io_msg = new Logger("pacahon", "io", "mstorage");

    try
    {
        Individual node;

        core_context = PThreadContext.create_new(node_id, "core_context-mstorage", log, null);
        l_context    = core_context;

        sticket = sys_ticket(core_context);
        node    = core_context.get_configuration();
        if (node.getStatus() == ResultCode.OK)
            log.trace_log_and_console("VEDA NODE CONFIGURATION: [%s]", node);

        log.trace("init core");

        sticket = sys_ticket(core_context, true);
        Ticket *guest_ticket = core_context.get_storage.get_ticket("guest", false);

        if (guest_ticket is null || guest_ticket.result == ResultCode.Ticket_not_found)
        {
            create_new_ticket("guest", "cfg:Guest", "900000000", "guest");
        }

        /////////////////////////////////////////////////////////////////////////////////////////////////////////
        if (node.getStatus() != ResultCode.OK)
        {
            core_context.reopen_ro_individuals_storage_db();
            core_context.reopen_ro_acl_storage_db();
            node = core_context.get_individual(&sticket, node_id, OptAuthorize.NO);

            log.trace_log_and_console("VEDA NODE CONFIGURATION:[%s]", node);
        }

        return;
    } catch (Throwable ex)
    {
        writeln("Exception: ", ex.msg);
        return;
    }
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
        receiveTimeout(dur!("msecs")(600),
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

        veda.storage.storage_manager.flush_int_module(P_MODULE.subject_manager, false);
        veda.mstorage.acl_manager.flush(false);
        veda.storage.storage_manager.flush_int_module(P_MODULE.ticket_manager, false);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////

private KeyValueDB inividuals_storage_r;

private Individual get_individual(Context ctx, Ticket *ticket, string uri)
{
    if (inividuals_storage_r is null)
        inividuals_storage_r = ctx.get_storage().get_inividuals_storage_r();

    Individual individual = Individual.init;

    if (inividuals_storage_r is null)
    {
        log.trace("ERR! storage not ready");
        return individual;
    }

    if (ticket is null)
    {
        log.trace("get_individual, uri=%s, ticket is null", uri);
        return individual;
    }

    inividuals_storage_r.get_individual(uri, individual);

    return individual;
}

private Ticket create_new_ticket(string user_login, string user_id, string duration = "40000", string ticket_id = null)
{
    Ticket     ticket;
    Individual new_ticket;

    ticket.result = ResultCode.Fail_Store;

    Resources type = [ Resource(ticket__Ticket) ];

    new_ticket.resources[ rdf__type ] = type;

    if (ticket_id !is null && ticket_id.length > 0)
        new_ticket.uri = ticket_id;
    else
    {
        UUID new_id = randomUUID();
        new_ticket.uri = new_id.toString();
    }

    new_ticket.resources[ ticket__login ] ~= Resource(user_login);
    new_ticket.resources[ ticket__accessor ] ~= Resource(user_id);
    new_ticket.resources[ ticket__when ] ~= Resource(getNowAsString());
    new_ticket.resources[ ticket__duration ] ~= Resource(duration);

    // store ticket
    string     ss_as_binobj = new_ticket.serialize();

    long       op_id;
    ResultCode rc =
        ticket_storage_module.save(P_MODULE.ticket_manager, OptAuthorize.NO, INDV_OP.PUT, null, new_ticket.uri, null, ss_as_binobj, -1, null,
                                   -1, 0,
                                   OptFreeze.NONE,
                                   op_id);
    ticket.result = rc;

    if (rc == ResultCode.OK)
    {
        subject2Ticket(new_ticket, &ticket);
        user_of_ticket[ ticket.id ] = new Ticket(ticket);
    }

    log.trace("create new ticket %s, login=%s, user=%s, start=%s, end=%s", ticket.id, ticket.user_login, ticket.user_uri, SysTime(ticket.start_time,
                                                                                                                                  UTC()).toISOExtString(),
              SysTime(ticket.end_time, UTC()).toISOExtString());

    return ticket;
}

auto         rnd               = Random(42);
const string empty_Sha256_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
public long  PASSWORD_LIFETIME;

private Ticket authenticate(Context ctx, string login, string password, string secret)
{
    //StopWatch sw; sw.start;

    Ticket ticket;
    Ticket sticket = ctx.sys_ticket(true);

    //if (trace_msg[ T_API_70 ] == 1)
    log.trace("authenticate, login=[%s] password=[%s], secret=[%s]", login, password, secret);

    ticket.result = ResultCode.Authentication_Failed;

    if (login == null || login.length < 3)
        return ticket;

    if (secret !is null && secret.length > 5 && password == empty_Sha256_hash)
    {
        ticket.result = ResultCode.Empty_password;
        return ticket;
    }

    if (secret !is null && secret.length > 5 && (password == null || password.length < 64))
    {
        ticket.result = ResultCode.Invalid_password;
        return ticket;
    }

    if (secret !is null && secret != "?" && secret.length < 6)
    {
        ticket.result = ResultCode.Invalid_secret;
        return ticket;
    }

    Individual[] candidate_users;
    string       query = "'" ~ veda_schema__login ~ "' == '" ~ replaceAll(login, regex(r"[-]", "g"), " +") ~ "'";

    ctx.get_vql().get(sticket.user_uri, query, null, null, 10, 10000, candidate_users, OptAuthorize.NO, false);
    auto storage = ctx.get_storage();
    if (storage is null)
    {
        log.trace("authenticate:fail authenticate, storage not ready");
        return ticket;
    }

    foreach (user; candidate_users)
    {
        string user_id = user.getFirstResource("v-s:owner").uri;
        if (user_id is null)
        {
            log.trace("ERR! authenticate:user id is null, user_indv=%s", user);
            continue;
        }

        string user_login = user.getFirstResource("v-s:login").data;
        if (user_login is null)
        {
            log.trace("ERR! authenticate:user login is null, user_indv=%s", user);
            continue;
        }

        if (icmp(user_login, login) != 0)
        {
            log.trace("ERR! authenticate:user login [%s] not equal request login [%s]", user_login, login);
            continue;
        }

        Individual iuser = get_individual(ctx, &sticket, user_id);

        if (iuser.getStatus() != ResultCode.OK)
        {
            log.trace("ERR! authenticate:user %s not found", user_id);
            continue;
        }

        string     exist_password;
        string     usesCredential_uri = user.getFirstLiteral("v-s:usesCredential");
        long       edited;

        Individual i_usesCredential;
        if (usesCredential_uri !is null)
        {
            log.trace("INFO! authenticate:found v-s:usesCredential, uri=%s", usesCredential_uri);
            i_usesCredential = get_individual(ctx, &sticket, usesCredential_uri);
            exist_password   = i_usesCredential.getFirstLiteral("v-s:password");
            edited           = i_usesCredential.getFirstDatetime("v-s:dateFrom");
        }
        else
        {
            exist_password = user.getFirstLiteral("v-s:password");

            i_usesCredential.uri = user.uri ~ "-crdt";
            i_usesCredential.addResource("rdf:type", Resource(DataType.Uri, "v-s:Credential"));
            i_usesCredential.addResource("v-s:password", Resource(DataType.String, exist_password));
            edited = Clock.currTime().toUnixTime();
            i_usesCredential.addResource("v-s:dateFrom", Resource(DataType.Datetime, edited));

            Transaction tnx;
            tnx.id            = -1;
            tnx.is_autocommit = true;
            OpResult op_res = add_to_transaction(
                                                 storage.get_acl_client(), tnx, &sticket, INDV_OP.PUT, &i_usesCredential, false, "",
                                                 OptFreeze.NONE, OptAuthorize.YES,
                                                 OptTrace.NONE);

            log.trace("INFO! authenticate: create v-s:Credential[%s], res=%s", i_usesCredential, op_res);
            user.addResource("v-s:usesCredential", Resource(DataType.Uri, i_usesCredential.uri));
            user.removeResource("v-s:password");

            tnx.id            = -1;
            tnx.is_autocommit = true;
            op_res            = add_to_transaction(
                                                   storage.get_acl_client(), tnx, &sticket, INDV_OP.PUT, &user, false, "",
                                                   OptFreeze.NONE,
                                                   OptAuthorize.YES,
                                                   OptTrace.NONE);

            log.trace("INFO! authenticate: update user[%s], res=%s", user, op_res);
        }

        string origin     = iuser.getFirstLiteral("v-s:origin");
        string old_secret = i_usesCredential.getFirstLiteral("v-s:secret");

        //if (origin !is null && origin == "External User")
        if (secret !is null && secret.length > 5)
        {
            if (old_secret is null)
            {
                log.trace("ERR! authenticate:update password: secret not found, user=[%s]", iuser.uri);
                ticket.result = ResultCode.Invalid_secret;
                remove_secret(i_usesCredential, iuser.uri, storage, &sticket);
                return ticket;
            }

            if (secret != old_secret)
            {
                log.trace("ERR! authenticate:request for update password: send secret not equal request secret [%s], user=[%s]", secret, iuser.uri);
                ticket.result = ResultCode.Invalid_secret;
                remove_secret(i_usesCredential, iuser.uri, storage, &sticket);
                return ticket;
            }


            long now              = Clock.currTime().toUnixTime();
            long prev_secret_date = i_usesCredential.getFirstDatetime("v-s:SecretDateFrom");
            if (now - prev_secret_date > 12 * 60 * 60)
            {
                ticket.result = ResultCode.Secret_expired;
                log.trace("ERR! authenticate:request new password, secret expired, login=[%s] password=[%s] secret=[%s]", login, password,
                          secret);
                return ticket;
            }


            if (exist_password == password)
            {
                log.trace("ERR! authenticate:update password: now password equal previous password, reject. user=[%s]", iuser.uri);
                ticket.result = ResultCode.New_password_is_equal_to_old;
                remove_secret(i_usesCredential, iuser.uri, storage, &sticket);
                return ticket;
            }

            if (password == empty_Sha256_hash)
            {
                log.trace("ERR! authenticate:update password: now password is empty, reject. user=[%s]", iuser.uri);
                ticket.result = ResultCode.Empty_password;
                remove_secret(i_usesCredential, iuser.uri, storage, &sticket);
                return ticket;
            }

            // update password
            i_usesCredential.setResources("v-s:password", [ Resource(DataType.String, password) ]);
            edited = Clock.currTime().toUnixTime();
            i_usesCredential.setResources("v-s:dateFrom", [ Resource(DataType.Datetime, edited) ]);
            i_usesCredential.removeResource("v-s:secret");

            Transaction tnx;
            tnx.id            = -1;
            tnx.is_autocommit = true;
            OpResult op_res = add_to_transaction(
                                                 storage.get_acl_client(), tnx, &sticket, INDV_OP.PUT, &i_usesCredential, false, "",
                                                 OptFreeze.NONE, OptAuthorize.YES,
                                                 OptTrace.NONE);

            if (op_res.result == ResultCode.OK)
            {
                ticket = create_new_ticket(login, user_id);
                log.trace("INFO! authenticate:update password [%s] for user, user=[%s]", password, iuser.uri);
            }
            else
            {
                ticket.result = ResultCode.Authentication_Failed;
                log.trace("ERR! authenticate:fail store new password [%s] for user, user=[%s]", password, iuser.uri);
            }

            return ticket;
        }
        else
        {
            bool is_request_new_password = false;

            if (PASSWORD_LIFETIME > 0)
            {
                long now = Clock.currTime().toUnixTime();
                if (now - edited > PASSWORD_LIFETIME)
                {
                    log.trace("ERR! authenticate:password is old, lifetime > %d days, user=%s", PASSWORD_LIFETIME / 60 / 60 / 24, user.uri);
                    is_request_new_password = true;
                }
            }

            if (secret == "?")
            {
                log.trace("ERR! authenticate:request for new password, user=%s", user.uri);
                is_request_new_password = true;
            }

            if (is_request_new_password == true)
            {
                log.trace("ERR! authenticate:request new password, login=[%s] password=[%s] secret=[%s]", login, password, secret);
                ticket.result = ResultCode.Password_expired;

                // generate new secret
                auto rnd      = Random(unpredictableSeed);
                auto n_secret = to!string(uniform(100000, 999999, rnd));

                long now = Clock.currTime().toUnixTime();
                if (old_secret !is null)
                {
                    long prev_secret_date = i_usesCredential.getFirstDatetime("v-s:SecretDateFrom");
                    if (now - prev_secret_date < 10 * 60)
                    {
                        ticket.result = ResultCode.Too_Many_Requests;
                        log.trace("ERR! authenticate:request new password, to many request, login=[%s] password=[%s] secret=[%s]", login, password,
                                  secret);
                        return ticket;
                    }
                }

                i_usesCredential.setResources("v-s:secret", [ Resource(DataType.String, n_secret) ]);
                i_usesCredential.setResources("v-s:SecretDateFrom", [ Resource(DataType.Datetime, now) ]);

                Transaction tnx;
                tnx.id            = -1;
                tnx.is_autocommit = true;
                OpResult op_res = add_to_transaction(
                                                     storage.get_acl_client(), tnx, &sticket, INDV_OP.PUT, &i_usesCredential, false, "",
                                                     OptFreeze.NONE, OptAuthorize.YES,
                                                     OptTrace.NONE);

                if (op_res.result != ResultCode.OK)
                {
                    log.trace("ERR! authenticate:fail store new secret, user=[%s]", iuser.uri);
                    return ticket;
                }

                string mailbox = user.getFirstLiteral("v-s:mailbox");

                if (mailbox !is null && mailbox.length > 3)
                {
                    Individual mail_with_secret;

                    mail_with_secret.uri = "d:mail_" ~ randomUUID().toString();

                    mail_with_secret.addResource("rdf:type", Resource(DataType.Uri, "v-s:Email"));
                    mail_with_secret.addResource("v-s:recipientMailbox", Resource(DataType.String, mailbox));
                    mail_with_secret.setResources("v-s:created", [ Resource(DataType.Datetime, Clock.currTime().toUnixTime()) ]);
                    mail_with_secret.addResource("v-s:messageBody", Resource(DataType.String, "your secret code is " ~ n_secret));

                    op_res = add_to_transaction(
                                                storage.get_acl_client(), tnx, &sticket, INDV_OP.PUT, &mail_with_secret, false, "",
                                                OptFreeze.NONE, OptAuthorize.YES,
                                                OptTrace.NONE);

                    if (op_res.result != ResultCode.OK)
                    {
                        log.trace("ERR! authenticate:fail store email with new secret, user=[%s]", iuser.uri);
                        return ticket;
                    }
                    else
                        log.trace("INFO! authenticate:send [%s] new secret [%s] to mailbox [%s], user=[%s]", mail_with_secret.uri, n_secret, mailbox,
                                  iuser.uri);
                }
                else
                {
                    log.trace("ERR! authenticate:mailbox not found, user=[%s]", iuser.uri);
                }


                return ticket;
            }


            if (exist_password !is null && password !is null && password.length > 63 && exist_password == password)
            {
                ticket = create_new_ticket(login, user_id);
                return ticket;
            }
        }
    }

    log.trace("ERR! authenticate:fail authenticate, login=[%s] password=[%s]", login, password);
    ticket.result = ResultCode.Authentication_Failed;
    return ticket;
}

private void remove_secret(ref Individual i_usesCredential, string user_uri, Storage storage, Ticket *sticket)
{
    string old_secret = i_usesCredential.getFirstLiteral("v-s:secret");

    if (old_secret !is null)
    {
        i_usesCredential.removeResource("v-s:secret");

        Transaction tnx;
        tnx.id            = -1;
        tnx.is_autocommit = true;
        OpResult op_res = add_to_transaction(
                                             storage.get_acl_client(), tnx, sticket, INDV_OP.PUT, &i_usesCredential, false, "",
                                             OptFreeze.NONE, OptAuthorize.YES,
                                             OptTrace.NONE);

        if (op_res.result != ResultCode.OK)
        {
            log.trace("ERR! authenticate:fail remove secret code for user, user=[%s]", user_uri);
        }
    }
}

public string execute_json(string in_msg, Context ctx)
{
    JSONValue res;
    JSONValue jsn;

    try
    {
        jsn = parseJSON(in_msg);
    }
    catch (Throwable tr)
    {
        log.trace("ERR! fail parse msg=%s, err=%s", in_msg, tr.msg);
        res[ "type" ]   = "OpResult";
        res[ "result" ] = ResultCode.Internal_Server_Error;
        res[ "op_id" ]  = -1;

        return res.toString();
    }
    //log.trace("get msg=%s", jsn);
    try
    {
        JSONValue fn = jsn[ "function" ];

        string    sfn = fn.str();

        if (sfn == "authenticate")
        {
            JSONValue login    = jsn[ "login" ];
            JSONValue password = jsn[ "password" ];

            string    secret = null;

            if (auto p = "secret" in jsn)
                secret = jsn[ "secret" ].str;

            Ticket ticket = authenticate(ctx, login.str, password.str, secret);

            res[ "type" ]     = "ticket";
            res[ "id" ]       = ticket.id;
            res[ "user_uri" ] = ticket.user_uri;
            res[ "user_login" ] = ticket.user_login;
            res[ "result" ]   = ticket.result;
            res[ "end_time" ] = ticket.end_time;

            //log.trace("authenticate: res=%s", res);
        }
        else if (sfn == "get_ticket_trusted")
        {
            JSONValue ticket_id = jsn[ "ticket" ];
            JSONValue login     = jsn[ "login" ];

            Ticket    ticket = get_ticket_trusted(ctx, ticket_id.str, login.str);

            res[ "type" ]     = "ticket";
            res[ "id" ]       = ticket.id;
            res[ "user_uri" ] = ticket.user_uri;
            res[ "user_login" ] = ticket.user_login;
            res[ "result" ]   = ticket.result;
            res[ "end_time" ] = ticket.end_time;
        }
        else if (sfn == "put" || sfn == "remove" || sfn == "add_to" || sfn == "set_in" || sfn == "remove_from")
        {
            OpResult[] rc;

            JSONValue  _ticket           = jsn[ "ticket" ];
            JSONValue  jassigned_modules = jsn[ "assigned_subsystems" ];

            long       assigned_subsystems = jassigned_modules.integer();

            JSONValue  event_id       = jsn[ "event_id" ];
            long       transaction_id = 0;

            Ticket     *ticket = ctx.get_storage().get_ticket(_ticket.str, false);

            if (sfn == "put")
            {
                JSONValue[] individuals_json = jsn[ "individuals" ].array;

                foreach (individual_json; individuals_json)
                {
                    Individual  individual = json_to_individual(individual_json);

                    Transaction tnx;
                    tnx.id            = transaction_id;
                    tnx.is_autocommit = true;
                    OpResult ires = add_to_transaction(
                                                       ctx.get_storage().get_acl_client(), tnx, ticket, INDV_OP.PUT, &individual, assigned_subsystems,
                                                       event_id.str,
                                                       OptFreeze.NONE, OptAuthorize.YES,
                                                       OptTrace.NONE);

                    //commit (OptAuthorize.YES, tnx);

                    rc ~= ires;
                    if (transaction_id <= 0)
                        transaction_id = ires.op_id;
                }
            }
            else if (sfn == "add_to")
            {
                JSONValue[] individuals_json = jsn[ "individuals" ].array;

                foreach (individual_json; individuals_json)
                {
                    Individual  individual = json_to_individual(individual_json);

                    Transaction tnx;
                    tnx.id            = transaction_id;
                    tnx.is_autocommit = true;
                    OpResult ires = add_to_transaction(
                                                       ctx.get_storage().get_acl_client(), tnx, ticket, INDV_OP.ADD_IN, &individual,
                                                       assigned_subsystems, event_id.str,
                                                       OptFreeze.NONE, OptAuthorize.YES,
                                                       OptTrace.NONE);

                    rc ~= ires;
                    if (transaction_id <= 0)
                        transaction_id = ires.op_id;
                }
            }
            else if (sfn == "set_in")
            {
                JSONValue[] individuals_json = jsn[ "individuals" ].array;

                foreach (individual_json; individuals_json)
                {
                    Individual  individual = json_to_individual(individual_json);

                    Transaction tnx;
                    tnx.id            = transaction_id;
                    tnx.is_autocommit = true;
                    OpResult ires = add_to_transaction(
                                                       ctx.get_storage().get_acl_client(), tnx, ticket, INDV_OP.SET_IN, &individual,
                                                       assigned_subsystems, event_id.str,
                                                       OptFreeze.NONE, OptAuthorize.YES,
                                                       OptTrace.NONE);

                    rc ~= ires;
                    if (transaction_id <= 0)
                        transaction_id = ires.op_id;
                }
            }
            else if (sfn == "remove_from")
            {
                JSONValue[] individuals_json = jsn[ "individuals" ].array;

                foreach (individual_json; individuals_json)
                {
                    Individual  individual = json_to_individual(individual_json);

                    Transaction tnx;
                    tnx.id            = transaction_id;
                    tnx.is_autocommit = true;
                    OpResult ires = add_to_transaction(
                                                       ctx.get_storage().get_acl_client(), tnx, ticket, INDV_OP.REMOVE_FROM, &individual,
                                                       assigned_subsystems,
                                                       event_id.str,
                                                       OptFreeze.NONE, OptAuthorize.YES,
                                                       OptTrace.NONE);

                    rc ~= ires;
                    if (transaction_id <= 0)
                        transaction_id = ires.op_id;
                }
            }
            else if (sfn == "remove")
            {
                JSONValue[] individuals_json = jsn[ "individuals" ].array;

                foreach (individual_json; individuals_json)
                {
                    Individual  individual = json_to_individual(individual_json);

                    Transaction tnx;
                    tnx.id            = transaction_id;
                    tnx.is_autocommit = true;
                    OpResult ires = add_to_transaction(
                                                       ctx.get_storage().get_acl_client(), tnx, ticket, INDV_OP.REMOVE, &individual,
                                                       assigned_subsystems, event_id.str,
                                                       OptFreeze.NONE, OptAuthorize.YES,
                                                       OptTrace.NONE);

                    rc ~= ires;
                    if (transaction_id <= 0)
                        transaction_id = ires.op_id;
                }
            }

            JSONValue[] all_res;
            foreach (rr; rc)
            {
                JSONValue ires;
                ires[ "result" ] = rr.result;
                ires[ "op_id" ]  = rr.op_id;
                all_res ~= ires;
            }

            res[ "type" ] = "OpResult";
            res[ "data" ] = all_res;
        }
        else if (sfn == "flush")
        {
            P_MODULE   f_module_id = cast(P_MODULE)jsn[ "module_id" ].integer;
            long       wait_op_id  = jsn[ "wait_op_id" ].integer;

            ResultCode rc;

            if (f_module_id == P_MODULE.subject_manager)
                rc = flush_storage();
            else if (f_module_id == P_MODULE.acl_preparer)
                rc = acl_module.flush(false);
            else if (f_module_id == cast(P_MODULE)MODULE.fulltext_indexer)
                flush_ext_module(f_module_id, wait_op_id);

            res[ "type" ]   = "OpResult";
            res[ "result" ] = ResultCode.OK;
            res[ "op_id" ]  = -1;
        }
        else if (sfn == "send_to_module")
        {
            P_MODULE   f_module_id = cast(P_MODULE)jsn[ "module_id" ].integer;
            string     msg         = jsn[ "msg" ].str;

            ResultCode rc;

            msg_to_module(f_module_id, msg, false);

            res[ "type" ]   = "OpResult";
            res[ "result" ] = ResultCode.OK;
            res[ "op_id" ]  = -1;
        }
        else if (sfn == "freeze")
        {
            ctx.freeze();
            res[ "type" ]   = "OpResult";
            res[ "result" ] = ResultCode.OK;
            res[ "op_id" ]  = -1;
        }
        else if (sfn == "unfreeze")
        {
            ctx.unfreeze();
            res[ "type" ]   = "OpResult";
            res[ "result" ] = ResultCode.OK;
            res[ "op_id" ]  = -1;
        }
        else
        {
            res[ "type" ]   = "OpResult";
            res[ "result" ] = ResultCode.Bad_Request;
            res[ "op_id" ]  = -1;
        }

        return res.toString();
    }
    catch (Throwable tr)
    {
        log.trace("ERR! fail execute msg=%s, err=%s", in_msg, tr.msg);
        res[ "type" ]   = "OpResult";
        res[ "result" ] = ResultCode.Internal_Server_Error;
        res[ "op_id" ]  = -1;

        return res.toString();
    }
}

private void freeze()
{
    indv_storage_thread.freeze(P_MODULE.subject_manager);
}

private void unfreeze()
{
    indv_storage_thread.unfreeze(P_MODULE.subject_manager);
}

private Ticket *[ string ] user_of_ticket;

private Ticket sys_ticket(Context ctx, bool is_new = false)
{
    Ticket ticket = get_global_systicket();

    if (ticket == Ticket.init || ticket.user_uri == "" || is_new)
    {
        try
        {
            ticket = create_new_ticket("veda", "cfg:VedaSystem", "90000000");

            long       op_id;
            Individual sys_ticket_link;
            sys_ticket_link.uri = "systicket";
            sys_ticket_link.addResource("rdf:type", Resource(DataType.Uri, "rdfs:Resource"));
            sys_ticket_link.addResource("v-s:resource", Resource(DataType.Uri, ticket.id));

            ticket_storage_module.save(P_MODULE.ticket_manager, OptAuthorize.NO, INDV_OP.PUT, null, sys_ticket_link.uri, null,
                                       sys_ticket_link.serialize(), -1, null,
                                       -1, 0, OptFreeze.NONE,
                                       op_id);

            Individual sys_account_permission;
            sys_account_permission.uri = "p:" ~ ticket.id;
            sys_account_permission.addResource("rdf:type", Resource(DataType.Uri, "v-s:PermissionStatement"));
            sys_account_permission.addResource("v-s:canCreate", Resource(DataType.Boolean, "true"));
            sys_account_permission.addResource("v-s:permissionObject", Resource(DataType.Uri, "v-s:AllResourcesGroup"));
            sys_account_permission.addResource("v-s:permissionSubject", Resource(DataType.Uri, "cfg:VedaSystem"));

            Transaction tnx;
            tnx.id            = -1;
            tnx.is_autocommit = true;
            OpResult opres = add_to_transaction(
                                                ctx.get_storage().get_acl_client(), tnx, &ticket, INDV_OP.PUT, &sys_account_permission, false, "srv",
                                                OptFreeze.NONE,
                                                OptAuthorize.NO,
                                                OptTrace.NONE);

            log.trace("systicket [%s] was created", ticket.id);

            if (opres.result == ResultCode.OK)
                log.trace("permission was created [%s]", sys_account_permission);
        }
        catch (Exception ex)
        {
            log.trace("sys_ticket:EX!%s", ex.msg);
        }

        if (ticket.user_uri == "")
            ticket.user_uri = "cfg:VedaSystem";

        set_global_systicket(ticket);
    }

    return ticket;
}

private OpResult[] commit(OptAuthorize opt_request, ref Transaction in_tnx)
{
    ResultCode rc;

    OpResult[] rcs;
    long       op_id;

    if (in_tnx.is_autocommit == false)
    {
        auto items = in_tnx.get_immutable_queue();

        log.trace("commit: items=%s", items);

        if (items.length > 0)
        {
            rc = indv_storage_thread.save(P_MODULE.subject_manager, opt_request, items, in_tnx.id, OptFreeze.NONE, op_id);

            log.trace("commit: rc=%s", rc);

            if (rc == ResultCode.OK)
            {
                MapResource rdfType;

                foreach (item; items)
                {
                    log.trace("commit: item.rc=%s", item.rc);
                    if (item.rc == ResultCode.OK)
                        rc = prepare_event(rdfType, item.prev_binobj, item.new_binobj, item.is_acl_element, item.is_onto, item.op_id);
                }
                rcs ~= OpResult(rc, op_id);
            }
        }
    }

    return rcs;
}


static const byte NEW_TYPE    = 0;
static const byte EXISTS_TYPE = 1;

private OpResult add_to_transaction(Authorization acl_client, ref Transaction tnx, Ticket *ticket, INDV_OP cmd, Individual *indv,
                                    long assigned_subsystems,
                                    string event_id,
                                    OptFreeze opt_freeze,
                                    OptAuthorize opt_request,
                                    OptTrace opt_trace)
{
    if (ticket !is null && get_global_systicket().user_uri == ticket.user_uri)
    {
        //log.trace("WARN! add_to_transaction: [%s %s] from sysuser, skip authorization", text(cmd), indv.uri);
        opt_request = OptAuthorize.NO;
    }

    //log.trace("add_to_transaction: %s %s", text(cmd), *indv);

    OpResult res = OpResult(ResultCode.Fail_Store, -1);

    if (ticket is null)
    {
        log.trace("ERR! add_to_transaction: %s %s, ticket is null", text(cmd), *indv);
        res = OpResult(ResultCode.Authentication_Failed, -1);
        return res;
    }

    try
    {
        if (indv !is null && (indv.uri is null || indv.uri.length < 2))
        {
            res.result = ResultCode.Invalid_Identifier;
            return res;
        }
        if (indv is null || (cmd != INDV_OP.REMOVE && indv.resources.length == 0))
        {
            res.result = ResultCode.No_Content;
            return res;
        }

        Tid         tid_subject_manager;

        bool        is_acl_element;
        bool        is_onto;

        MapResource rdfType;
        Resources   _types = set_map_of_type(indv, rdfType);

        string      prev_state;
        Individual  prev_indv;

//        bool        is_new = false;

//        if (indv.getFirstInteger("v-s:updateCounter", 0) == 0 && cmd == INDV_OP.PUT)
//        {
//            is_new = true;
//			  log.trace("INFO! %s is new, use UPSERT", indv.uri);
//        }

//        if (is_new == false)
        {
            try
            {
                prev_state = indv_storage_thread.find(P_MODULE.subject_manager, indv.uri);

                if ((prev_state is null ||
                     prev_state.length == 0) && (cmd == INDV_OP.ADD_IN || cmd == INDV_OP.SET_IN || cmd == INDV_OP.REMOVE_FROM))
                    log.trace("ERR! add_to_transaction, cmd=%s: not read prev_state uri=[%s]", text(cmd), indv.uri);
            }
            catch (Exception ex)
            {
                res.result = ResultCode.Unprocessable_Entity;
                log.trace("ERR! add_to_transaction: not read prev_state uri=[%s], ex=%s", indv.uri, ex.msg);
                return res;
            }

            if (prev_state !is null)
            {
                int code = prev_indv.deserialize(prev_state);
                if (code < 0)
                {
                    log.trace("ERR! add_to_transaction: invalid prev_state [%s], uri=%s", prev_state, indv.uri);
                    res.result = ResultCode.Unprocessable_Entity;
                    return res;
                }

                if (cmd == INDV_OP.REMOVE)
                {
                    indv.deserialize(prev_state);
                    _types = set_map_of_type(indv, rdfType);
                }

                if (opt_request == OptAuthorize.YES && cmd != INDV_OP.REMOVE)
                {
                    if (indv.isExists("v-s:deleted", true))
                    {
                        if (acl_client.authorize(indv.uri, ticket.user_uri, Access.can_delete, true, null, null, null) != Access.can_delete)
                        {
                            // для устаноки аттрибута v-s:deleted у индивида проверим доступность бита Delete
                            log.trace("ERR! add_to_transaction: Not Authorized, user [%s] request [can delete] [%s] ", ticket.user_uri, indv.uri);
                            res.result = ResultCode.Not_Authorized;
                            return res;
                        }
                    }
                    else if (acl_client.authorize(indv.uri, ticket.user_uri, Access.can_update, true, null, null, null) != Access.can_update)
                    {
                        // для обновляемого индивида проверим доступность бита Update
                        log.trace("ERR! add_to_transaction: Not Authorized, user [%s] request [can update] [%s] ", ticket.user_uri, indv.uri);
                        res.result = ResultCode.Not_Authorized;
                        return res;
                    }

                    // найдем какие из типов были добавлены по сравнению с предыдущим набором типов
                    foreach (rs; _types)
                    {
                        string   itype = rs.get!string;

                        Resource rr = rdfType.get(itype, Resource.init);

                        if (rr !is Resource.init)
                        {
                            rr.info          = EXISTS_TYPE;
                            rdfType[ itype ] = rr;
                        }
                    }
                }
            }
        }

        if (opt_request == OptAuthorize.YES && cmd != INDV_OP.REMOVE)
        {
            // для новых типов проверим доступность бита Create
            foreach (key, rr; rdfType)
            {
                if (rr.info == NEW_TYPE)
                {
                    if (acl_client.authorize(key, ticket.user_uri, Access.can_create, true, null, null, null) != Access.can_create)
                    {
                        log.trace("ERR! add_to_transaction: Not Authorized, user [%s] request [can_create] [%s] ", ticket.user_uri, key);
                        res.result = ResultCode.Not_Authorized;
                        return res;
                    }
                }
            }
        }

        long   update_counter = prev_indv.getFirstInteger("v-s:updateCounter", 0);
        update_counter++;
        string new_state;

        if (rdfType.anyExists(owl_tags) == true)
            is_onto = true;

        if (rdfType.anyExists(veda_schema__PermissionStatement) == true || rdfType.anyExists(veda_schema__Membership) == true ||
            rdfType.anyExists(veda_schema__PermissionFilter) == true)
            is_acl_element = true;

        if (cmd == INDV_OP.REMOVE)
        {
            prev_indv.setResources("v-s:deleted", [ Resource(true) ]);

            new_state = prev_indv.serialize();
            if (new_state.length > max_size_of_individual)
            {
                res.result = ResultCode.Size_too_large;
                return res;
            }

            immutable TransactionItem ti =
                immutable TransactionItem(INDV_OP.PUT, ticket.user_uri, indv.uri, prev_state, new_state, update_counter,
                                          event_id, is_acl_element, is_onto, assigned_subsystems);

            immutable TransactionItem ti1 =
                immutable TransactionItem(INDV_OP.REMOVE, ticket.user_uri, indv.uri, prev_state, null, update_counter,
                                          event_id, is_acl_element, is_onto, assigned_subsystems);

            if (tnx.is_autocommit)
            {
                res.result =
                    indv_storage_thread.save(P_MODULE.subject_manager, opt_request, [ ti ], tnx.id, opt_freeze,
                                             res.op_id);

                if (res.result == ResultCode.OK)
                {
                    res.result =
                        indv_storage_thread.save(P_MODULE.subject_manager, opt_request, [ ti1 ], tnx.id, opt_freeze,
                                                 res.op_id);
                }
            }
            else
            {
                tnx.add_immutable(ti);
                tnx.add_immutable(ti1);
            }
        }
        else
        {
            if (cmd == INDV_OP.ADD_IN || cmd == INDV_OP.SET_IN || cmd == INDV_OP.REMOVE_FROM)
            {
                //log.trace("++ add_to_transaction (%s), prev_indv: %s, op_indv: %s", text (cmd), prev_indv, *indv);
                indv = indv_apply_cmd(cmd, &prev_indv, indv);
                //log.trace("++ add_to_transaction (%s), final indv: %s", text (cmd), *indv);
            }

            indv.setResources("v-s:updateCounter", [ Resource(update_counter) ]);

            new_state = indv.serialize();
            if (new_state.length > max_size_of_individual)
            {
                res.result = ResultCode.Size_too_large;
                return res;
            }

            immutable TransactionItem ti =
                immutable TransactionItem(INDV_OP.PUT, ticket.user_uri, indv.uri, prev_state, new_state, update_counter,
                                          event_id, is_acl_element, is_onto, assigned_subsystems);

            if (tnx.is_autocommit)
            {
                res.result =
                    indv_storage_thread.save(P_MODULE.subject_manager, opt_request, [ ti ], tnx.id, opt_freeze,
                                             res.op_id);
            }
            else
            {
                tnx.add_immutable(ti);
            }
            //log.trace("res.result=%s", res.result);
        }

        if (tnx.is_autocommit && res.result == ResultCode.OK)
            res.result = prepare_event(rdfType, prev_state, new_state, is_acl_element, is_onto, res.op_id);

        return res;
    }
    finally
    {
        if (res.result != ResultCode.OK)
            log.trace("ERR! add_to_transaction (%s): no store individual: errcode=[%s], ticket=[%s], indv=[%s]", text(cmd), text(res.result),
                      ticket !is null ? text(*ticket) : "null",
                      indv !is null ? text(*indv) : "null");

        if (opt_trace == OptTrace.TRACE)
            log.trace("add_to_transaction [%s] = %s", indv.uri, res);
    }
}

private ResultCode prepare_event(ref MapResource rdfType, string prev_binobj, string new_binobj, bool is_acl_element, bool is_onto,
                                 long op_id)
{
    ResultCode res;

    Tid        tid_acl;

    if (rdfType.anyExists(veda_schema__PermissionStatement) == true || rdfType.anyExists(veda_schema__Membership) == true ||
        rdfType.anyExists(veda_schema__PermissionFilter) == true)
    {
        tid_acl = getTid(P_MODULE.acl_preparer);
        if (tid_acl != Tid.init)
        {
            send(tid_acl, CMD_PUT, prev_binobj, new_binobj, op_id);
        }
    }

    res = ResultCode.OK;

    return res;
}

private Resources set_map_of_type(Individual *indv, ref MapResource rdfType)
{
    Resources _types;

    if (indv is null)
        return _types;

    _types = indv.resources.get(rdf__type, Resources.init);

    foreach (idx, rs; _types)
        _types[ idx ].info = NEW_TYPE;
    setMapResources(_types, rdfType);

    return _types;
}

public ResultCode flush_storage()
{
    ResultCode rc;

    rc = ResultCode.OK;
    return rc;
}

private void flush_ext_module(P_MODULE f_module, long wait_op_id)
{
    Tid tid = getTid(P_MODULE.subject_manager);

    if (tid != Tid.init)
    {
        send(tid, CMD_COMMIT, f_module, wait_op_id);
    }
}

private ResultCode msg_to_module(P_MODULE f_module, string msg, bool is_wait)
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

string allow_trusted_group = "cfg:TrustedAuthenticationUserGroup";

/**
   Доверенная аутентификация
   Params:
            ticket = имя пользователя, входящего в группу [cfg:SuperUser]
            login = имя пользователя, кому будет выдан новый тикет

   Returns:
            экземпляр структуры Ticket
 */
private Ticket get_ticket_trusted(Context ctx, string tr_ticket_id, string login)
{
    Ticket ticket;

    //if (trace_msg[ T_API_60 ] == 1)
    log.trace("INFO: request trusted authenticate, ticket=[%s] login=[%s]", tr_ticket_id, login);

    ticket.result = ResultCode.Authentication_Failed;

    if (login == null || login.length < 1 || tr_ticket_id.length < 6)
    {
        log.trace("WARN: trusted authenticate: invalid login [%s] or ticket [%s]", login, ticket);
        return ticket;
    }

    Ticket *tr_ticket = ctx.get_storage().get_ticket(tr_ticket_id, false);
    if (tr_ticket.result == ResultCode.OK)
    {
        bool      is_allow_trusted = false;

        OutBuffer trace_acl = new OutBuffer();
        ctx.get_rights_origin_from_acl(tr_ticket, tr_ticket.user_uri, trace_acl, null);
        foreach (rr; trace_acl.toString().split('\n'))
        {
            string[] cc = rr.split(";");

            if (cc.length == 3)
            {
                string resource_group = cc[ 0 ];
                string subject_group  = cc[ 1 ];
                string right          = cc[ 2 ];

                if (subject_group == allow_trusted_group)
                {
                    is_allow_trusted = true;
                    break;
                }
            }
        }

        if (is_allow_trusted)
        {
            login = replaceAll(login, regex(r"[-]", "g"), " +");

            Ticket       sticket = sys_ticket(ctx);

            string       query = "'" ~ veda_schema__login ~ "' == '" ~ login ~ "'";

            Individual[] candidate_users = ctx.get_individuals_via_query(sticket.user_uri, query, OptAuthorize.NO);

            if (candidate_users.length == 0)
                log.trace("ERR! trusted authenticate: not found candidate users, query=%s", query);

            foreach (user; candidate_users)
            {
                string user_id = user.getFirstResource("v-s:owner").uri;
                string f_login = user.getFirstResource("v-s:login").data;
                if (user_id is null)
                    continue;

                ticket = create_new_ticket(f_login, user_id);

                log.trace("INFO! trusted authenticate, result ticket=[%s]", ticket);
                return ticket;
            }
        }
        else
        {
            log.trace("ERR! trusted authenticate: User [%s] must be a member of group [%s]", *tr_ticket, allow_trusted_group);
        }
    }
    else
        log.trace("WARN! trusted authenticate: problem ticket [%s]", ticket);

    log.trace("ERR! failed trusted authenticate, ticket=[%s] login=[%s]", tr_ticket_id, login);

    ticket.result = ResultCode.Authentication_Failed;
    return ticket;
}
