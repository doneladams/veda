module veda.storage.storage;

import std.conv, std.datetime, std.uuid, std.stdio;
import veda.common.logger, veda.common.type, veda.core.common.transaction, veda.storage.common;
import veda.onto.individual, veda.onto.resource, veda.core.common.know_predicates, veda.util.module_info, veda.core.util.utils;
import veda.authorization.authorization;

public abstract class Storage
{
    string name;
    Ticket *[ string ] user_of_ticket;
    long   last_ticket_manager_op_id = 0;

    Logger log;

    /**
       Количество индивидуалов в базе данных
     */
    abstract long count_individuals();

    abstract KeyValueDB get_tickets_storage_r();
    abstract KeyValueDB get_inividuals_storage_r();

    public string get_binobj_from_individual_storage(string uri)
    {
        string res = get_inividuals_storage_r.get_binobj(uri);

        if (res !is null && res.length < 10)
            log.trace_log_and_console("ERR! get_individual_from_storage, found invalid BINOBJ, uri=%s", uri);

        return res;
    }

    public void get_obj_from_individual_storage(string uri, ref Individual indv)
    {
        get_inividuals_storage_r.get_individual(uri, indv);
    }

    private void reopen_ro_ticket_manager_db()
    {
        get_tickets_storage_r().reopen();
    }

    public Ticket create_new_ticket(string user_login, string user_id, string duration, string ticket_id, bool is_trace = false)
    {
        if (is_trace)
            log.trace("create_new_ticket, ticket__accessor=%s", user_id);

        Ticket     ticket;
        Individual new_ticket;

        ticket.result = ResultCode.FailStore;

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

        return ticket;
    }

    public Ticket *get_systicket_from_storage()
    {
        Individual indv_systicket_link;

        get_tickets_storage_r().get_individual("systicket", indv_systicket_link);

        string systicket_id;

        if (indv_systicket_link.getStatus == ResultCode.Ok)
        {
            systicket_id = indv_systicket_link.getFirstLiteral("v-s:resource");
        }
        else
        {
            log.trace("SYSTICKET NOT FOUND");
        }

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

                Individual ticket;
                get_tickets_storage_r().get_individual(ticket_id, ticket);

                if (ticket.getStatus() == ResultCode.Ok)
                {
                    tt = new Ticket;
                    subject2Ticket(ticket, tt);
                    tt.result               = ResultCode.Ok;
                    user_of_ticket[ tt.id ] = tt;
                }
                else if (ticket.getStatus() == ResultCode.NotFound)
                {
                    tt        = new Ticket;
                    tt.result = ResultCode.TicketNotFound;

                    if (is_trace)
                        log.trace("тикет не найден в базе, id=%s", ticket_id);
                }
                else
                {
                    tt        = new Ticket;
                    tt.result = ResultCode.UnprocessableEntity;
                    log.trace("ERR! storage.get_ticket, invalid individual, uri=%s, errcode=%s", ticket_id, ticket.getStatus());
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
                        Ticket guest_ticket = create_new_ticket("guest", "cfg:Guest", "900000000", "guest");
                        tt = &guest_ticket;
                    }
                    else
                    {
                        tt        = new Ticket;
                        tt.id     = "?";
                        tt.result = ResultCode.TicketExpired;
                    }
                    return tt;
                }
                else
                {
                    tt.result = ResultCode.Ok;
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

