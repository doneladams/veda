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

void main(string[] args)
{
    Connector connector = new Connector();
    connector.connect("127.0.0.1", 9999);

    MDB_env *env;
    MDB_txn *txn;
    MDB_dbi dbi;
    MDB_cursor *cursor;

    mdb_env_create(&env);

    mdb_env_set_maxdbs(env, 1);
    stdout.writeln();
    stdout.writefln("open result %d", mdb_env_open(env, cast(const(char*))args[1], 0, 777));
    
    stdout.writefln("txn begin %d", mdb_txn_begin(env, null, MDB_RDONLY, &txn));
    stdout.writefln("dbi open %d", mdb_dbi_open(txn, null, 0, &dbi));
    stdout.writefln("cursor open %d", mdb_cursor_open(txn, dbi, &cursor));
    
    int rc = 0;
    while (rc == 0) {
        MDB_val key, data;

        rc = mdb_cursor_get(cursor, &key, &data, MDB_cursor_op.MDB_NEXT);
        if (rc != 0)
            break;
        string key_str = cast(string)key.mv_data[0 .. key.mv_size];
        string data_str = cast(string)data.mv_data[0 .. data.mv_size];

        if (key_str == "summ_hash_this_db")
            continue;

        Individual individual;
        string new_state; 

        if (key_str != "systicket") {
            individual.deserialize(data_str);
            new_state = individual.serialize_msgpack();
        } else {
            Individual systicket;
            systicket.uri = "systicket";
            systicket.addResource("rdf:type", Resource(DataType.Uri,"ticket:Ticket"));
            systicket.addResource("ticket:id", Resource(DataType.Uri, data_str));
            new_state = systicket.serialize_msgpack();
        }

        

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
    }
	
/+    TcpSocket listener = new TcpSocket();

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
