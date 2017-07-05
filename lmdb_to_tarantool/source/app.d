import std.stdio, std.socket;
import individual;
import connector, type, resource, requestresponse;

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
    Connector connector = new Connector();
    connector.connect("127.0.0.1", 9999);
	
    TcpSocket listener = new TcpSocket();

    listener.bind(getAddress("localhost", 11113)[ 0 ]);
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
    listener.listen(65535);

    try
    {
        while (true)
        {
            Socket socket = listener.accept();
			string cborv = recv(socket);
			Individual individual;
			individual.deserialize(cborv);
            string new_state = individual.serialize_msgpack();
            Individual big_individual;
            big_individual.addResource("uri", Resource(DataType.Uri, "1"));
            big_individual.uri = "1";
            big_individual.addResource("new_state", Resource(DataType.String, new_state));
            string bin = big_individual.serialize_msgpack();
            RequestResponse rr = connector.put(false, "cfg:VedaSystem", [bin]);
            if (rr.common_rc != ResultCode.OK) {
                stderr.writefln("@COMMON ERR WITH CODE %d", rr.common_rc);
                stderr.writeln(new_state);
                break;
            } else if (rr.op_rc[0] != ResultCode.OK) {
                stderr.writefln("@OP ERR WITH CODE %d", rr.common_rc);
                stderr.writeln(new_state);
                break;
            }
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
