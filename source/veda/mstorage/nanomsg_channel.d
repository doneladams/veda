module veda.mstorage.nanomsg_channel;

import core.thread, std.stdio, std.format, std.datetime, std.concurrency, std.conv, std.outbuffer, std.string, std.uuid, std.path, std.json;
import veda.core.common.context, veda.core.util.utils, veda.onto.onto, veda.core.impl.thread_context, veda.core.common.define;
import kaleidic.nanomsg.nano, veda.mstorage.server, veda.search.xapian.xapian_search, veda.util.properd, veda.core.impl.app_context_creator;

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-mstorage", "log", "N-CHANNEL");
    return _log;
}
// ////// ////// ///////////////////////////////////////////

void nanomsg_channel(string thread_name)
{
    int    sock;
    string bind_url = null;

    try
    {
        string[ string ] properties;
        properties = readProperties("./veda.properties");
        bind_url   = properties.as!(string)("main_module_url") ~ "\0";
    }
    catch (Throwable ex)
    {
        log.trace("ERR! unable read ./veda.properties");
        return;
    }

    try
    {
        Context                      context;

        core.thread.Thread.getThis().name = thread_name;

        sock = nn_socket(AF_SP, NN_REP);
        if (sock < 0)
        {
            log.trace("ERR! cannot create socket");
            return;
        }
        if (nn_bind(sock, cast(char *)bind_url) < 0)
        {
            log.trace("ERR! cannot bind to socket, url=%s", bind_url);
            return;
        }
        log.trace("success bind to %s", bind_url);

        if (context is null)
        {
            context = create_new_ctx(thread_name, log);
            context.set_az(get_acl_client(log));
            context.set_vql(new XapianSearch(context));
        }

        long luplft = context.get_configuration().getFirstInteger("cfg:user_password_lifetime");

        if (luplft > 0)
            PASSWORD_LIFETIME = luplft * 24 * 60 * 60;
//		else
//			PASSWORD_LIFETIME = 60 * 24 * 60 * 60;

        // SEND ready
        receive((Tid tid_response_reciever)
                {
                    send(tid_response_reciever, true);
                });

        while (true)
        {
            try
            {
                char *buf  = cast(char *)0;
                int  bytes = nn_recv(sock, &buf, NN_MSG, 0);
                if (bytes >= 0)
                {
                    string req = cast(string)buf[ 0..bytes ];
                    //log.trace("RECEIVED [%d](%s)", bytes, req);

                    string rep;

                    if (req[ 0 ] == '{')
                    {
                        //log.trace ("is json");
                        rep = execute_json(req, context);
                    }

                    nn_freemsg(buf);

                    bytes = nn_send(sock, cast(char *)rep, rep.length, 0);
//                    log.trace("SENDING (%s) %d bytes", rep, bytes);
                }
            }
            catch (Throwable tr)
            {
                log.trace("ERR! MAIN LOOP", tr.info);
            }
        }
    }
    finally
    {
        writeln("exit form thread ", thread_name);
    }
}
