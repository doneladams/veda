/**
 * filltext query module
 */
import std.stdio, std.socket, std.conv;
import core.thread; import core.atomic;
import veda.common.logger, veda.core.common.context, veda.core.impl.thread_context;

class HandlerThread : Thread
{
    Socket  socket;
    Context context;

public:
    this(Socket socket, Context context)
    {
        this.socket  = socket;
        this.context = context;
        super(&run);
    }

private:
    void run()
    {
        string request = _recv(socket);

        // TODO: надо из request вытащить нижеуказанные параметры
        string _ticket;
        string query_str;
        string sort_str;
        string db_str;
        int    from, top, limit;
		//
		
        Ticket *ticket;

        ticket = context.get_ticket(_ticket);

        SearchResult res = context.get_individuals_ids_via_query(ticket, query_str, sort_str, db_str, from, top, limit, null, false);

        // TODO: необходимо перед отправкой серелизовать [res]

        string response = text(res);

        _send(socket, response);

        socket.close();

        ctx_pool.free_context(context);
    }
}

private string _recv(Socket socket)
{
    ubyte[] buf          = new ubyte[ 4 ];
    long    request_size = 0;
    socket.receive(buf);
    for (int i = 0; i < 4; i++)
        request_size = (request_size << 8) + buf[ i ];

    ubyte[] request = new ubyte[ request_size ];
    socket.receive(request);
    stdout.writeln("@REQ ", request);

    return cast(string)request;
}

private void _send(Socket socket, string data)
{
    ubyte[] buf           = new ubyte[ 4 ];
    long    response_size = data.length;
    stdout.writefln("RESP SIZE %d", response_size);
    buf                    = new ubyte[ 4 + response_size ];
    buf[ 0 ]               = cast(byte)((response_size >> 24) & 0xFF);
    buf[ 1 ]               = cast(byte)((response_size >> 16) & 0xFF);
    buf[ 2 ]               = cast(byte)((response_size >> 8) & 0xFF);
    buf[ 3 ]               = cast(byte)(response_size & 0xFF);
    buf[ 4 .. buf.length ] = cast(ubyte[])data;
    socket.send(buf);
}


void handle_request()
{
}

private Logger log;

class ContextPool
{
    private shared bool[ Context ] pool;

    synchronized Context allocate_context()
    {
        foreach (ctx, state; pool)
        {
            if (state == false)
            {
                pool[ ctx ] = true;
                return ctx;
            }
        }

        Context new_ctx = PThreadContext.create_new("cfg:standart_node", "ft-query", "", log, null);
        pool[ new_ctx ] = true;
        return new_ctx;
    }

    synchronized void free_context(Context ctx)
    {
        pool[ ctx ] = false;
    }
}

shared ContextPool ctx_pool;

void main()
{
    TcpSocket listener = new TcpSocket();

    listener.bind(getAddress("localhost", 11112)[ 0 ]);
    listener.listen(65535);

    log = new Logger("veda-core-ft-query", "log", "");

    ctx_pool = new ContextPool();
	Context context = ctx_pool.allocate_context();
	ctx_pool.free_context(context);

    while (true)
    {
        Socket  socket  = listener.accept();
        context = ctx_pool.allocate_context();
        auto    ht      = new HandlerThread(socket, context);
        ht.start();
    }
}

