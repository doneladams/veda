module veda.connector.connector;

private
{
    import std.stdio;
    import msgpack;
    import std.socket;
    import veda.core.common.context;
}

class RequestResponse
{
    ResultCode common_rc;
    ResultCode[] op_rc;
    string[] msgpacks;
}

class Connector 
{
    public static RequestResponse Put(string addr, ushort port, bool need_auth, string user_uri, 
        string[] individuals)
    {
        RequestResponse request_response = new RequestResponse();
        Packer packer = Packer(false);
        stderr.writeln("PACK PUT REQUEST");
        packer.beginArray(individuals.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < individuals.length; i++)
            packer.pack(individuals[i]);

        long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

        byte[4] size_buf;
        size_buf[0] = cast(byte)((request_size >> 24) & 0xFF);
        size_buf[1] = cast(byte)((request_size >> 16) & 0xFF);
        size_buf[2] = cast(byte)((request_size >> 8) & 0xFF);
        size_buf[3] = cast(byte)(request_size & 0xFF);

        TcpSocket s = new TcpSocket();
        s.connect(new InternetAddress("127.0.0.1", 9999));

        s.send(size_buf);
        s.send([ cast(byte)1 ]);
        s.send(packer.stream.data);
       
        stderr.writeln("RECEIVE SIZE BUF ", 
            s.receive(size_buf));
        stderr.writeln("RESPONSE SIZE BUF ", size_buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++) 
            response_size = (response_size << 8) + size_buf[i];       
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[response_size];
        stderr.writeln("RECEIVE RESPONSE ", 
            s.receive(response));
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

    public static RequestResponse Get(string addr, ushort port, bool need_auth, string user_uri, 
        string[] individuals)
    {
        RequestResponse request_response = new RequestResponse();
        Packer packer = Packer(false);
        stderr.writeln("PACK PUT REQUEST");
        packer.beginArray(individuals.length + 2);
        packer.pack(need_auth, user_uri);
        for (int i = 0; i < individuals.length; i++)
            packer.pack(individuals[i]);

        long request_size = packer.stream.data.length;
        stderr.writeln("DATA SIZE ", request_size);

        byte[4] size_buf;
        size_buf[0] = cast(byte)((request_size >> 24) & 0xFF);
        size_buf[1] = cast(byte)((request_size >> 16) & 0xFF);
        size_buf[2] = cast(byte)((request_size >> 8) & 0xFF);
        size_buf[3] = cast(byte)(request_size & 0xFF);

        TcpSocket s = new TcpSocket();
        s.connect(new InternetAddress("127.0.0.1", 9999));

        s.send(size_buf);
        s.send([ cast(byte)2 ]);
        s.send(packer.stream.data);
       
        stderr.writeln("RECEIVE SIZE BUF ", 
            s.receive(size_buf));
        stderr.writeln("RESPONSE SIZE BUF ", size_buf);
        long response_size = 0;
        for (int i = 0; i < 4; i++) 
            response_size = (response_size << 8) + size_buf[i];       
        stderr.writeln("RESPONSE SIZE ", response_size);
        ubyte[] response = new ubyte[response_size];
        stderr.writeln("RECEIVE RESPONSE ", 
            s.receive(response));
        s.close();
        

        StreamingUnpacker unpacker = 
            StreamingUnpacker(response);

        if (unpacker.execute()) 
        {  
            auto obj = unpacker.unpacked[0];
            request_response.common_rc = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = individuals.length;
            
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