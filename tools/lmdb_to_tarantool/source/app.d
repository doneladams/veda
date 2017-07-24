import std.stdio, std.socket;
import individual;
import connector, type, resource, requestresponse, queue;

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


    Queue uris_queue;
	const string   uris_db_path        = "./data/uris";

    uris_queue = new Queue(uris_db_path, "uris-db", Mode.RW);
    stderr.writefln("open queue [%s]", uris_queue);
    uris_queue.open();

    try
    {
        while (true)
        {
            Socket socket = listener.accept();
			string cborv = recv(socket);
			Individual individual;
			individual.deserialize(cborv);
			
			uris_queue.push(individual.uri);
			
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

        if (uris_queue !is null)
        {
            uris_queue.close();
            uris_queue = null;
        }   
	     }
}
