module veda.connector.connector;

private
{
    import std.stdio;
    import msgpack;
    import veda.core.common.context;
    import veda.connector.requestresponse;
}

version (std_socket)
{
    import std.socket;
}
version (WebServer)
{
    import vibe.core.net;
}

class Connector
{
    public static ubyte[] buf;

    public static RequestResponse put(string addr, ushort port, bool need_auth, string user_uri,
                                      string[] individuals)
    {
        RequestResponse request_response = new RequestResponse();
        Packer          packer           = Packer(false);

        stderr.writeln("PACK PUT REQUEST");
        packer.beginArray(individuals.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < individuals.length; i++)
            packer.pack(individuals[ i ]);

        long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

		if (buf.length == 0)
			buf = new ubyte [4];
			
        buf[ 0 ] = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ] = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ] = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ] = cast(byte)(request_size & 0xFF);

        version (WebServer)
        {
            TCPConnection s = connectTCP(addr, port);
        }

        version (std_socket)
        {
            TcpSocket s = new TcpSocket();
            s.connect(new InternetAddress("127.0.0.1", 9999));
        }

        version (WebServer)
        {
            s.write(buf);
            s.write([ cast(ubyte)1 ]);
            s.write(cast(ubyte[])packer.stream.data);
        }
        version (std_socket)
        {
	        s.send(buf);
	        s.send([ cast(byte)1 ]);
	        s.send(packer.stream.data);
        }

        version (WebServer)
        {
            s.read(buf);
            long receive_size = buf.length;
        }

        version (std_socket)
        {
            long receive_size = s.receive(buf);
        }
        stderr.writeln("RECEIVE SIZE BUF ", receive_size);


        stderr.writeln("RESPONSE SIZE BUF ", buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++)
            response_size = (response_size << 8) + buf[ i ];
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[ response_size ];

        version (WebServer)
        {
            s.read(response);
            receive_size = response.length;
        }
        version (std_socket)
        {
            receive_size = s.receive(response);
        }
        stderr.writeln("RECEIVE RESPONSE ", receive_size);

        s.close();


        StreamingUnpacker unpacker =
            StreamingUnpacker(response);

        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = 0;

            stderr.writeln("OP RESULT = ", obj.via.uinteger);
            for (int i = 1; i < unpacker.unpacked.length; i++)
            {
                obj                             = unpacker.unpacked[ i ];
                request_response.op_rc[ i - 1 ] = cast(ResultCode)obj.via.uinteger;
                stderr.writeln("PUT RESULT = ", obj.via.uinteger);
            }
        }
        else
            stderr.writefln("@ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public static RequestResponse get(string addr, ushort port, bool need_auth, string user_uri,
                                      string[] uris)
    {
        RequestResponse request_response = new RequestResponse();
        Packer          packer           = Packer(false);

        stderr.writefln("PACK GET REQUEST %s %d", addr, port);
        packer.beginArray(uris.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

		if (buf.length == 0)
			buf = new ubyte [4];

        buf[ 0 ] = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ] = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ] = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ] = cast(byte)(request_size & 0xFF);

        stderr.writeln("CONNECT");

        version (WebServer)
        {
            TCPConnection s = connectTCP(addr, port);
        }

        version (std_socket)
        {
            TcpSocket s = new TcpSocket();
            s.connect(new InternetAddress("127.0.0.1", 9999));
        }

        stderr.writeln("SEND 1");

        version (WebServer)
        {
            s.write(buf);
            s.write([ cast(ubyte)2 ]);
            s.write(cast(ubyte[])packer.stream.data);
        }
        version (std_socket)
        {
            s.send(buf);
            s.send([ cast(byte)2 ]);
            s.send(packer.stream.data);
        }

        version (WebServer)
        {
        	s.read(buf);
            long receive_size = buf.length; 
        }

        version (std_socket)
        {
            long receive_size = s.receive(buf);
        }
        stderr.writeln("RECEIVE SIZE BUF ", receive_size);

        stderr.writeln("RESPONSE SIZE BUF ", buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++)
            response_size = (response_size << 8) + buf[ i ];
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[ response_size ];

        version (WebServer)
        {
            s.read(response);
            receive_size = response.length; 
        }
        version (std_socket)
        {
            receive_size = s.receive(response);
        }
        stderr.writeln("RECEIVE RESPONSE ", receive_size);

        s.close();


        StreamingUnpacker unpacker =
            StreamingUnpacker(response);

        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = uris.length;

            stderr.writeln("OP RESULT = ", obj.via.uinteger);
            for (int i = 1; i < unpacker.unpacked.length; i += 2)
            {
                obj                             = unpacker.unpacked[ i ];
                request_response.op_rc[ i - 1 ] = cast(ResultCode)obj.via.uinteger;
                if (request_response.op_rc[ i - 1 ] == ResultCode.OK)
                    request_response.msgpacks[ i - 1 ] = cast(string)unpacker.unpacked[ i + 1 ].via.raw;
                stderr.writeln("PUT RESULT = ", obj.via.uinteger);
            }
        }
        else
            stderr.writefln("@ERR ON UNPACKING RESPONSE");

        return request_response;
    }
}