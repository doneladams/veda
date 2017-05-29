/**
 * filltext query module
 */
import std.stdio;
import std.socket;
import core.thread;

class HandlerThread : Thread
{
    Socket socket;
public:
    this(Socket socket)
    {
        this.socket = socket;
        super(&run);
    }

private:
    void run()
    {
        ubyte[] buf          = new ubyte[ 4 ];
        long    request_size = 0;
        socket.receive(buf);
        for (int i = 0; i < 4; i++)
            request_size = (request_size << 8) + buf[ i ];

        ubyte[] request = new ubyte[ request_size ];
        socket.receive(request);
        stdout.writeln("@REQ ", request);

        ubyte[] response      = cast(ubyte[])(cast(string)request ~ " RESPONSE");
        long    response_size = response.length;
        stdout.writefln("RESP SIZE %d", response_size);
        buf                    = new ubyte[ 4 + response_size ];
        buf[ 0 ]               = cast(byte)((response_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((response_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((response_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(response_size & 0xFF);
        buf[ 4 .. buf.length ] = response;
        socket.send(buf);
        socket.close();
    }
}


void handle_request()
{
}

void main()
{
    TcpSocket listener = new TcpSocket();

    listener.bind(getAddress("localhost", 11112)[ 0 ]);
    listener.listen(65535);
    while (true)
    {
        Socket socket = listener.accept();
        new HandlerThread(socket).start();
    }
}