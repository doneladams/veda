module veda.server.ticket;

import std.uuid, std.conv, std.stdio;
import veda.common.type, veda.onto.individual, veda.onto.resource, veda.core.common.context, veda.core.common.know_predicates;
import veda.core.util.utils;

// alias veda.server.storage_manager ticket_storage_module;
alias veda.server.tt_storage_manager subject_storage_module;

public Ticket create_new_ticket(string user_id, string duration, string ticket_id)
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

    new_ticket.resources[ ticket__accessor ] ~= Resource(user_id);
    new_ticket.resources[ ticket__when ] ~= Resource(getNowAsString());
    new_ticket.resources[ ticket__duration ] ~= Resource(duration);

    // store ticket
    string     ss_as_binobj = new_ticket.serialize();

    long       op_id;
    // ResultCode rc = ticket_storage_module.put(P_MODULE.ticket_manager, false, null, type, new_ticket.uri, null, ss_as_binobj, -1, null, -1, false, op_id);
    ResultCode rc = subject_storage_module.put(P_MODULE.subject_manager, false, "cfg:VedaSystem", type, new_ticket.uri, null, ss_as_binobj, -1, null, -1, false,
                op_id);
    ticket.result = rc;

    if (rc == ResultCode.OK)
    {
        subject2Ticket(new_ticket, &ticket);
        //user_of_ticket[ ticket.id ] = new Ticket(ticket);
        
		//log.trace("server:send ticket to TT %s", new_ticket);
        //subject_storage_module.put(P_MODULE.subject_manager, false, "cfg:VedaSystem", type, new_ticket.uri, null, ss_as_binobj, -1, null, -1, false,
        //                                  op_id);        
    }

    return ticket;
}

private void subject2Ticket(ref Individual ticket, Ticket *tt, bool trace = false)
{
    string when;
    long   duration;

    tt.id       = ticket.uri;
    tt.user_uri = ticket.getFirstLiteral(ticket__accessor);
    when        = ticket.getFirstLiteral(ticket__when);
    string dd = ticket.getFirstLiteral(ticket__duration);

    try
    {
        duration = parse!uint (dd);
    }
    catch (Exception ex)
    {
        writeln("Ex!: ", __FUNCTION__, ":", text(__LINE__), ", ", ex.msg);
    }

    if (tt.user_uri is null)
    {
        //if (trace_msg[ T_API_10 ] == 1)
        //  log.trace("found a session ticket is not complete, the user can not be found.");
    }

    if (tt.user_uri !is null && (when is null || duration < 10))
    {
        //if (trace)
        //    log.trace("found a session ticket is not complete, we believe that the user has not been found.");
        tt.user_uri = null;
    }

    if (when !is null)
    {
        // if (trace)
        //     log.trace("session ticket %s Ok, user=%s, when=%s, duration=%d", tt.id, tt.user_uri, when,
        //               duration);

        tt.end_time = stringToTime(when) + duration * 10_000_000;
    }
}
