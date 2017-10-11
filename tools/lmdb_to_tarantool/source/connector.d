module connector;

private
{
    import core.thread;
    import std.stdio;
    import msgpack;
    import requestresponse, type;
}

    import std.socket;


const MAX_SIZE_OF_PACKET = 1024*1024*10;

class Connector
{
    public ubyte[] buf;
    public string  addr;
    public ushort  port;

    public TcpSocket s;

    public void connect(string addr, ushort port)
    {
        this.addr = addr;
        this.port = port;

        s = new TcpSocket();
        for (;; )
        {
            try
            {
                stderr.writefln("CONNECT STD %s %d", addr, port);
                s.connect(new InternetAddress(addr, port));
            }
            catch (Exception e)
            {
                Thread.sleep(dur!("seconds")(3));
                continue;
            }
            break;
        }
        stderr.writefln("CONNECTED STD");
    
    }


    public RequestResponse put(bool need_auth, string user_uri, string[] individuals)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			stderr.writefln("ERR! connector.put, code=%s", request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	
		if (individuals.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			stderr.writefln("ERR! connector.put, code=%s", request_response.common_rc);
			//printPrettyTrace(stderr);						
			return request_response;
		}	
				
        Packer          packer           = Packer(false);

        //stderr.writeln("PACK PUT REQUEST");
        packer.beginArray(individuals.length + 3);
        packer.pack(INDV_OP.PUT, need_auth, user_uri);
        for (int i = 0; i < individuals.length; i++)
            packer.pack(individuals[ i ]);

        long request_size = packer.stream.data.length;
        //stderr.writeln("DATA SIZE ", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {

            s.send(buf);
            

        
            buf.length = 4;
            long receive_size = s.receive(buf);
            
            //stderr.writeln("RECEIVE SIZE BUF ", receive_size);


            //stderr.writeln("RESPONSE SIZE BUF ", buf);
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];
            //stderr.writeln("RESPONSE SIZE ", response_size);

			if (response_size > MAX_SIZE_OF_PACKET)
			{
				request_response.common_rc = ResultCode.Size_too_large;
				stderr.writefln("ERR! connector.put, code=%s", request_response.common_rc);
				return request_response;
			}

            response = new ubyte[ response_size ];

            receive_size = s.receive(response);
            //stderr.writeln("RECEIVE RESPONSE ", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                stderr.writefln("@RECONNECT PUT REQUEST");
                close();
                connect(addr, port);
                continue;
            }
            break;
        }

        StreamingUnpacker unpacker =
            StreamingUnpacker(response);

        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = 0;

            //stderr.writeln("OP RESULT = ", obj.via.uinteger);
            for (int i = 1; i < unpacker.unpacked.length; i++)
            {
                obj                             = unpacker.unpacked[ i ];
                request_response.op_rc[ i - 1 ] = cast(ResultCode)obj.via.uinteger;
                //stderr.writeln("PUT RESULT = ", obj.via.uinteger);
            }
            //stderr.writeln("OP_RC ", request_response.op_rc);
        }
        else
            stderr.writefln("@ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public RequestResponse get(bool need_auth, string user_uri, string[] uris, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
        		stderr.writefln("@CONNECTOR ERR USER URI [%s]", user_uri);
			request_response.common_rc = ResultCode.Not_Authorized;
			stderr.writefln("ERR! connector.get[%s], code=%s", uris, request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	
		if (uris.length == 0)
		{
            stderr.writefln("@CONNECTOR ERR URIS");
			request_response.common_rc = ResultCode.No_Content;
			stderr.writefln("ERR! connector.get[%s], code=%s", uris, request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            stderr.writefln("connector.get PACK GET REQUEST need_auth=%b, user_uri=%s, uris=%s", need_auth, user_uri, uris);

        packer.beginArray(uris.length + 3);
        packer.pack(INDV_OP.GET, need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        stderr.writefln("connector.get DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            s.send(buf);

	        if (trace)
		        stderr.writefln("connector.get SEND %s", buf);

            buf.length = 4;
            long receive_size = s.receive(buf);
            
            if (trace)
                stderr.writefln("connector.get RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                stderr.writefln("connector.get RESPONSE SIZE BUF %s", buf);                
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                stderr.writefln("connector.get RESPONSE SIZE %d", response_size);

			if (response_size > MAX_SIZE_OF_PACKET)
			{
                stderr.writefln("connector.get RESPONSE SIZE BUF %s %s", buf, cast(char[])buf);

				request_response.common_rc = ResultCode.Size_too_large;
				stderr.writefln("ERR! connector.get[%s], code=%s", uris, request_response.common_rc);
				return request_response;
			}

            response = new ubyte[ response_size ];

            receive_size = s.receive(response);
            if (trace)
                stderr.writefln("connector.get RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                stderr.writefln ("connector.get @RECONNECT GET REQUEST");
                close();
                connect(addr, port);
                continue;
            }
            break;
        }


        StreamingUnpacker unpacker =
            StreamingUnpacker(response);
        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = uris.length;

            if (trace)
                stderr.writefln("connector.get OP RESULT = %d", obj.via.uinteger);
                
            for (int i = 1, j = 0; i < unpacker.unpacked.length; i += 2, j++)
            {
                obj                         = unpacker.unpacked[ i ];
                request_response.op_rc[ j ] = cast(ResultCode)obj.via.uinteger;
                if (request_response.op_rc[ j ] == ResultCode.OK)
                    request_response.msgpacks[ j ] = cast(string)unpacker.unpacked[ i + 1 ].via.raw;
                if (trace)
                    stderr.writefln("connector.get GET RESULT = %d", obj.via.uinteger);
            }
        }
        else
            stderr.writefln("connector.get @ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public RequestResponse authorize(string user_uri, string[] uris, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			stderr.writefln("ERR! connector.authorize, code=%s", request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	
		if (uris.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			stderr.writefln("ERR! connector.authorize, code=%s", request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            stderr.writefln("connector.authorize PACK AUTHORIZE REQUEST user_uri=%s, uris=%s", user_uri, uris);

        packer.beginArray(uris.length + 3);
        packer.pack(INDV_OP.AUTHORIZE, false, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        stderr.writefln("connector.authorize DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            s.send(buf);

	        if (trace)
		        stderr.writefln("connector.authorize SEND %s", buf);


            buf.length = 4;
            long receive_size = s.receive(buf);
            
            if (trace)
                stderr.writefln("connector.authorize RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                stderr.writefln("connector.authorize RESPONSE SIZE BUF %s %s", buf, cast(char[])buf);
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                stderr.writefln("connector.authorize RESPONSE SIZE %d", response_size);

			if (response_size > MAX_SIZE_OF_PACKET)
			{
				request_response.common_rc = ResultCode.Size_too_large;
				stderr.writefln("ERR! connector.authorize, code=%s", request_response.common_rc);
				return request_response;
			}

            response = new ubyte[ response_size ];

            receive_size = s.receive(response);
            if (trace)
                stderr.writefln("connector.authorize RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                stderr.writefln ("connector.authorize @RECONNECT AUTHORIZE REQUEST");
                close();
                connect(addr, port);
                continue;
            }
            break;
        }


        StreamingUnpacker unpacker = StreamingUnpacker(response);

        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.rights.length   = uris.length;

            if (trace)
                stderr.writefln("connector.authorize OP RESULT = %d, unpacker.unpacked.length=%d", obj.via.uinteger, unpacker.unpacked.length);
                
            for (int i = 1, j = 0; i < unpacker.unpacked.length; i += 3, j++)
            {
                obj                         = unpacker.unpacked[ i ];
                request_response.op_rc[ j ] = cast(ResultCode)obj.via.uinteger;
                request_response.rights[ j ] = cast(ubyte)unpacker.unpacked[ i + 1 ].via.uinteger;
                if (trace)
                    stderr.writefln("connector.authorize AUTHORIZE RESULT: op_rc=%d, right=%d", request_response.op_rc[ j ], request_response.rights[ j ]);
            }
        }
        else
            stderr.writefln("connector.authorize @ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public RequestResponse remove(bool need_auth, string user_uri, string[] uris, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			stderr.writefln("ERR! connector.remove: need_auth=%s, user_uri=%s, uris=[%s] code=%s", need_auth, user_uri, uris, request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	
		if (uris.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			stderr.writefln("ERR! connector.remove: need_auth=%s, user_uri=%s, uris=[%s] code=%s", need_auth, user_uri, uris, request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            stderr.writefln("connector.get PACK REMOVE REQUEST need_auth=%b, user_uri=%s, uris=%s", need_auth, user_uri, uris);

        packer.beginArray(uris.length + 3);
        packer.pack(INDV_OP.REMOVE, need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        stderr.writefln("connector.remove DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            s.send(buf);

	        if (trace)
		        stderr.writefln("connector.remove SEND %s", buf);


            buf.length = 4;
            long receive_size = s.receive(buf);
            
            if (trace)
                stderr.writefln("connector.remove RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                stderr.writefln("connector.remove RESPONSE SIZE BUF %s", buf);
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                stderr.writefln("connector.remove RESPONSE SIZE %d", response_size);

			if (response_size > MAX_SIZE_OF_PACKET)
			{
				request_response.common_rc = ResultCode.Size_too_large;
				stderr.writefln("ERR! connector.remove, code=%s", request_response.common_rc);
				return request_response;
			}

            response = new ubyte[ response_size ];

            receive_size = s.receive(response);
            if (trace)
                stderr.writefln("connector.remove RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                stderr.writefln ("connector.remove @RECONNECT REMOVE REQUEST");
                close();
                connect(addr, port);
                continue;
            }
            break;
        }


        StreamingUnpacker unpacker =
            StreamingUnpacker(response);

        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = uris.length;

            if (trace)
                stderr.writefln("connector.remove OP RESULT = %d", obj.via.uinteger);
            stderr.writefln("connector.remove OP RESULT = %d", obj.via.uinteger);
                
            for (int i = 1; i < unpacker.unpacked.length; i++)
            {
                obj                             = unpacker.unpacked[ i ];
                request_response.op_rc[ i - 1 ] = cast(ResultCode)obj.via.uinteger;
            }
        }
        else
            stderr.writefln("connector.remove @ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    void close()
    {
        s.close();
    }

    public RequestResponse get_ticket(string[] ticket_ids, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

        // stderr.writefln("@TICKET IDS %s", ticket_ids);

		if (ticket_ids.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			stderr.writefln("ERR! connector.get_ticket[%s], code=%s", ticket_ids, request_response.common_rc);
			//printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            stderr.writefln("connector.get_ticket PACK GET_TICKET REQUEST ticket_ids=[%s]",  ticket_ids);

        packer.beginArray(ticket_ids.length + 3);
        packer.pack(INDV_OP.GET_TICKET, false, "cfg:VedaSystem");
        for (int i = 0; i < ticket_ids.length; i++)
            packer.pack(ticket_ids[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        stderr.writefln("connector.get_ticket DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            s.send(buf);

	        if (trace)
		        stderr.writefln("connector.get_ticket SEND %s", buf);

            buf.length = 4;
            long receive_size = s.receive(buf);
            
            if (trace)
                stderr.writefln("connector.get_ticket RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                stderr.writefln("connector.get_ticket RESPONSE SIZE BUF %s", buf);                
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                stderr.writefln("connector.get_ticket RESPONSE SIZE %d", response_size);

			if (response_size > MAX_SIZE_OF_PACKET)
			{
                stderr.writefln("connector.get RESPONSE SIZE BUF %s %s", buf, cast(char[])buf);

				request_response.common_rc = ResultCode.Size_too_large;
				stderr.writefln("ERR! connector.get_ticket[%s], code=%s", ticket_ids, request_response.common_rc);
				return request_response;
			}

            response = new ubyte[ response_size ];

            receive_size = s.receive(response);
            if (trace)
                stderr.writefln("connector.get_ticket RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                stderr.writefln ("connector.get_ticket @RECONNECT GET_TICKET REQUEST");
                close();
                connect(addr, port);
                continue;
            }
            break;
        }


        StreamingUnpacker unpacker =
            StreamingUnpacker(response);
        if (unpacker.execute())
        {
            auto obj = unpacker.unpacked[ 0 ];
            request_response.common_rc       = cast(ResultCode)(obj.via.uinteger);
            request_response.op_rc.length    = unpacker.unpacked.length - 1;
            request_response.msgpacks.length = ticket_ids.length;

            if (trace)
                stderr.writefln("connector.get_ticket OP RESULT = %d", obj.via.uinteger);
                
            for (int i = 1, j = 0; i < unpacker.unpacked.length; i += 2, j++)
            {
                obj                         = unpacker.unpacked[ i ];
                request_response.op_rc[ j ] = cast(ResultCode)obj.via.uinteger;
                // stderr.writeln("@J ", j, request_response.op_rc[ j ]);
                if (request_response.op_rc[ j ] == ResultCode.OK)
                    request_response.msgpacks[ j ] = cast(string)unpacker.unpacked[ i + 1 ].via.raw;
                if (trace)
                    stderr.writefln("connector.get_ticket GET RESULT = %d", obj.via.uinteger);
            }
        }
        else
            stderr.writefln("connector.get_ticket @ERR ON UNPACKING RESPONSE");

        return request_response;
    }
}