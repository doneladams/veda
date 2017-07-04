import std.stdio, std.socket;
import individual;

private string recv(Socket socket)
{
    ubyte[] buf          = new ubyte[ 4 ];
    long    request_size = 0;
    socket.receive(buf);
    for (int i = 0; i < 4; i++)
        request_size = (request_size << 8) + buf[ i ];

    ubyte[] request = new ubyte[ request_size ];
    socket.receive(request);
    stderr.writefln("@REQ [%s]", cast(string)request);

    return cast(string)request;
}

void main()
{
	
    TcpSocket listener = new TcpSocket();

    listener.bind(getAddress("localhost", 11113)[ 0 ]);
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    listener.listen(65535);

    try
    {
        while (true)
        {
            Socket socket = listener.accept();
			stdout.writefln("accepted");
			string cborv = recv(socket);
			Individual individual;
			individual.deserialize(cborv);
			socket.close();
        }
    }
    catch (Exception ex)
    {
        //printPrettyTrace(stderr);
        stderr.writefln("@ERR %s", ex.msg);
        listener.close();
    }
}
