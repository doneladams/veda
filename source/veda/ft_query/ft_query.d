/**
 * filltext query module
 */
import std.stdio, std.socket, std.conv;
import core.thread;
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
        string 		 _ticket;
        string       query_str;
        string		 sort_str;
        string       db_str;
        int          from, top, limit;

        Ticket       *ticket;
        ticket = context.get_ticket(_ticket);

        SearchResult res = context.get_individuals_ids_via_query(ticket, query_str, sort_str, db_str, from, top, limit, null, false);

        // TODO: необходимо перед отправкой серелизовать [res]

        string response = text(res);

        _send(socket, response);

        socket.close();
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

void main()
{
    TcpSocket listener = new TcpSocket();

    listener.bind(getAddress("localhost", 11112)[ 0 ]);
    listener.listen(65535);

    Logger  log = new Logger("veda-core-ft-query", "log", "");

    Context context;
    context = PThreadContext.create_new("cfg:standart_node", "ft-query", "", log, null);

    while (true)
    {
        Socket socket = listener.accept();
        auto   ht     = new HandlerThread(socket, context);

        //ht.start(); пока запуск нитней отключен, так как сначала нужно сделат пулл из Context

        ht.run(); // здесь не запуск нити, а исполнение в текущей нити
    }
}