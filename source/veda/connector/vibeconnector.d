module veda.connector.vibeconnector;

private
{
    import std.stdio;
    import msgpack;
    import veda.core.common.context;
    import vibe.core.net;
    import veda.connector.requestresponse;
}

class VibeConnector 
{
    public static RequestResponse put(string addr, ushort port, bool need_auth, string user_uri, 
        string[] individuals)
    {
        RequestResponse request_response = new RequestResponse();
        Packer packer = Packer(false);
        stderr.writeln("VIBE PACK PUT REQUEST");
        packer.beginArray(individuals.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < individuals.length; i++)
            packer.pack(individuals[i]);

        long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

        ubyte[4] size_buf;
        size_buf[0] = cast(ubyte)((request_size >> 24) & 0xFF);
        size_buf[1] = cast(ubyte)((request_size >> 16) & 0xFF);
        size_buf[2] = cast(ubyte)((request_size >> 8) & 0xFF);
        size_buf[3] = cast(ubyte)(request_size & 0xFF);

        TCPConnection s = connectTCP(addr, port);
        // TcpSocket s = new TcpSocket();
        // s.connect(new InternetAddress("127.0.0.1", 9999));

        s.write(size_buf);
        s.write([ cast(ubyte)1 ]);
        s.write(cast(ubyte[])packer.stream.data);
       
        // stderr.writeln("RECEIVE SIZE BUF ", 
            // s.read(size_buf));
        s.read(size_buf);
        stderr.writeln("RESPONSE SIZE BUF ", size_buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++) 
            response_size = (response_size << 8) + size_buf[i];       
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[response_size];
        // stderr.writeln("RECEIVE RESPONSE ", 
            // s.read(response));
        s.read(response);
        s.close();
        

        StreamingUnpacker unpacker = 
            StreamingUnpacker(response);

        if (unpacker.execute()) 
        {  
            auto obj = unpacker.unpacked[0];
            request_response.common_rc = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = 0;
            
            stderr.writeln("OP RESULT = ", obj.via.uinteger);
            for (int i = 1; i < unpacker.unpacked.length; i++)
            {
                obj = unpacker.unpacked[i];
                request_response.op_rc[i - 1] = cast(ResultCode)obj.via.uinteger;
                stderr.writeln("PUT RESULT = ", obj.via.uinteger);
            }
        } else 
            stderr.writefln("@ERR ON UNPACKING RESPONSE");
            
        return request_response;
    }

    public static RequestResponse get(string addr, ushort port, bool need_auth, string user_uri, 
        string[] uris)
    {
        RequestResponse request_response = new RequestResponse();
        Packer packer = Packer(false);
        stderr.writeln("VIBE PACK GET REQUEST");
        packer.beginArray(uris.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[i]);

                long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

        ubyte[4] size_buf;
        size_buf[0] = cast(ubyte)((request_size >> 24) & 0xFF);
        size_buf[1] = cast(ubyte)((request_size >> 16) & 0xFF);
        size_buf[2] = cast(ubyte)((request_size >> 8) & 0xFF);
        size_buf[3] = cast(ubyte)(request_size & 0xFF);

        TCPConnection s = connectTCP(addr, port);
        // TcpSocket s = new TcpSocket();
        // s.connect(new InternetAddress("127.0.0.1", 9999));

        s.write(size_buf);
        s.write([ cast(ubyte)2 ]);
        s.write(cast(ubyte[])packer.stream.data);
       
        // stderr.writeln("RECEIVE SIZE BUF ", 
            // s.read(size_buf));
        s.read(size_buf);
        stderr.writeln("RESPONSE SIZE BUF ", size_buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++) 
            response_size = (response_size << 8) + size_buf[i];       
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[response_size];
        // stderr.writeln("RECEIVE RESPONSE ", 
            // s.read(response));
        s.read(response);
        s.close();
        

        StreamingUnpacker unpacker = 
            StreamingUnpacker(response);

        if (unpacker.execute()) 
        {  
            auto obj = unpacker.unpacked[0];
            request_response.common_rc = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = uris.length;
            
            stderr.writeln("OP RESULT = ", obj.via.uinteger);
            for (int i = 1; i < unpacker.unpacked.length; i += 2)
            {
                obj = unpacker.unpacked[i];
                request_response.op_rc[i - 1] = cast(ResultCode)obj.via.uinteger;
                if (request_response.op_rc[i - 1] == ResultCode.OK)
                    request_response.msgpacks[i - 1] = cast(string)unpacker.unpacked[i + 1].via.raw;
                stderr.writeln("PUT RESULT = ", obj.via.uinteger);
            }
        } else 
            stderr.writefln("@ERR ON UNPACKING RESPONSE");
            
        return request_response;
    }
}