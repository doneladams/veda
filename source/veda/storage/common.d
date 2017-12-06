module veda.storage.common;

import std.conv, std.datetime, std.uuid;
import veda.common.logger;
import veda.common.type, veda.core.common.transaction;
import veda.onto.individual, veda.onto.resource, veda.core.common.know_predicates, veda.util.module_info, veda.core.util.utils;

/// Режим работы хранилища
enum DBMode
{
    /// чтение
    R  = true,

    /// чтение/запись
    RW = false
}

public interface KeyValueDB
{
    public string find(OptAuthorize op_auth, string user_uri, string uri, bool return_value = true);
    public void open();
    public void reopen();
    public void close();
    public long count_entries();

    public void flush(int force);
    public ResultCode put(OptAuthorize op_auth, string user_id, string in_key, string in_value, long op_id);
    public ResultCode remove(OptAuthorize op_auth, string user_uri, string in_key);
}

public class Storage
{
    string     name;
    Ticket *[ string ] user_of_ticket;
    long       last_ticket_manager_op_id = 0;
    KeyValueDB tickets_storage_r;
    Logger     log;

    abstract public long last_op_id();
    abstract public OpResult put(OptAuthorize op_auth, immutable TransactionItem ti);
    abstract public OpResult[] put(OptAuthorize op_auth, immutable(TransactionItem)[] items);
    abstract public OpResult remove(OptAuthorize op_auth, string user_uri, string in_key);
    abstract public string find(OptAuthorize op_auth, string user_uri, string uri, bool return_value = true);
    //public string find_ticket(string ticket_id);

    abstract public ubyte authorize(string user_uri, string uri, bool trace);
    abstract public void flush(int force);
    abstract public void reopen();
    abstract public void open();
    abstract public void close();
    abstract long count_entries();

    private void reopen_ro_ticket_manager_db()
    {
        if (tickets_storage_r !is null)
            tickets_storage_r.reopen();
    }

    public Ticket create_new_ticket(string user_id, string duration, string ticket_id, bool is_trace = false)
    {
        if (is_trace)
            log.trace("create_new_ticket, ticket__accessor=%s", user_id);

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

        new_ticket.resources[ ticket__accessor ] ~= Resource(user_id);
        new_ticket.resources[ ticket__when ] ~= Resource(getNowAsString());
        new_ticket.resources[ ticket__duration ] ~= Resource(duration);

        version (WebServer)
        {
            subject2Ticket(new_ticket, &ticket);
            user_of_ticket[ ticket.id ] = new Ticket(ticket);
        }

        return ticket;
    }

    public Ticket *get_systicket_from_storage()
    {
        string systicket_id = tickets_storage_r.find(OptAuthorize.NO, null, "systicket");

        if (systicket_id is null)
            log.trace("SYSTICKET NOT FOUND");

        return get_ticket(systicket_id, false);
    }

    public Ticket *get_ticket(string ticket_id, bool is_trace, bool is_systicket = false)
    {
        //StopWatch sw; sw.start;

        try
        {
            Ticket *tt;
            if (ticket_id is null || ticket_id == "" || ticket_id == "systicket")
                ticket_id = "guest";

            tt = user_of_ticket.get(ticket_id, null);

            if (tt is null)
            {
                string when     = null;
                int    duration = 0;

                MInfo  mi = get_info(MODULE.ticket_manager);

                //log.trace ("last_ticket_manager_op_id=%d, mi.op_id=%d,  mi.committed_op_id=%d", last_ticket_manager_op_id, mi.op_id, mi.committed_op_id);
                if (last_ticket_manager_op_id < mi.op_id)
                {
                    last_ticket_manager_op_id = mi.op_id;
                    this.reopen_ro_ticket_manager_db();
                }

                string ticket_str = tickets_storage_r.find(OptAuthorize.NO, null, ticket_id);
                if (ticket_str !is null && ticket_str.length > 120)
                {
                    tt = new Ticket;
                    Individual ticket;

                    if (ticket.deserialize(ticket_str) > 0)
                    {
                        subject2Ticket(ticket, tt);
                        tt.result               = ResultCode.OK;
                        user_of_ticket[ tt.id ] = tt;

                        if (is_trace)
                            log.trace("тикет найден в базе, id=%s", ticket_id);
                    }
                    else
                    {
                        tt.result = ResultCode.Unprocessable_Entity;
                        log.trace("ERR! invalid individual=%s", ticket_str);
                    }
                }
                else
                {
                    tt        = new Ticket;
                    tt.result = ResultCode.Ticket_not_found;

                    if (is_trace)
                        log.trace("тикет не найден в базе, id=%s", ticket_id);
                }
            }
            else
            {
                if (is_trace)
                    log.trace("тикет нашли в кеше, id=%s, end_time=%d", tt.id, tt.end_time);

                SysTime now = Clock.currTime();
                if (now.stdTime >= tt.end_time && !is_systicket)
                {
                    log.trace("ticket %s expired, user=%s, start=%s, end=%s, now=%s", tt.id, tt.user_uri, SysTime(tt.start_time,
                                                                                                                  UTC()).toISOExtString(),
                              SysTime(tt.end_time, UTC()).toISOExtString(), now.toISOExtString());

                    if (ticket_id == "guest")
                    {
                        Ticket guest_ticket = create_new_ticket("cfg:Guest", "900000000", "guest");
                        tt = &guest_ticket;
                    }
                    else
                    {
                        tt        = new Ticket;
                        tt.id     = "?";
                        tt.result = ResultCode.Ticket_expired;
                    }
                    return tt;
                }
                else
                {
                    tt.result = ResultCode.OK;
                }

                if (is_trace)
                    log.trace("ticket: %s", *tt);
            }
            return tt;
        }
        finally
        {
            //stat(CMD_GET, sw);
        }
    }

    private ModuleInfoFile[ MODULE ] info_r__2__pmodule;
    public MInfo get_info(MODULE module_id)
    {
        ModuleInfoFile mdif = info_r__2__pmodule.get(module_id, null);

        if (mdif is null)
        {
            mdif                            = new ModuleInfoFile(text(module_id), log, OPEN_MODE.READER);
            info_r__2__pmodule[ module_id ] = mdif;
        }
        MInfo info = mdif.get_info();
        return info;
    }
}

string access_to_pretty_string(const ubyte src)
{
    string res = "";

    if (src & Access.can_create)
        res ~= "C ";
    if (src & Access.can_read)
        res ~= "R ";
    if (src & Access.can_update)
        res ~= "U ";
    if (src & Access.can_delete)
        res ~= "D ";
    if (src & Access.cant_create)
        res ~= "!C ";
    if (src & Access.cant_read)
        res ~= "!R ";
    if (src & Access.cant_update)
        res ~= "!U ";
    if (src & Access.cant_delete)
        res ~= "!D ";

    return res;
}

