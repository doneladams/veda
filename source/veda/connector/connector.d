module veda.connector.connector;

private
{
    import core.thread;
    import std.stdio;
    import backtrace.backtrace, Backtrace = backtrace.backtrace;
    import msgpack;
    import veda.core.common.context, veda.connector.requestresponse, veda.common.type, veda.common.logger;
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
    Logger         log;
    public ubyte[] buf;
    public string  addr;
    public ushort  port;

    version (std_socket)
    {
        public TcpSocket s;
    }

    version (WebServer)
    {
        public TCPConnection s;
    }

    this(Logger _log)
    {
        log = _log;
    }

    public void connect(string addr, ushort port)
    {
        this.addr = addr;
        this.port = port;

        version (WebServer)
        {
            for (;; )
            {
                try
                {
                    log.trace("CONNECT WEB SERVER %s %d", addr, port);
                    s = connectTCP(addr, port);
                }
                catch (Exception e)
                {
                    Thread.sleep(dur!("seconds")(3));
                    continue;
                }
                break;
            }
            log.trace("CONNECTED WEB SERVER");
        }

        version (std_socket)
        {
            s = new TcpSocket();
            for (;; )
            {
                try
                {
                    log.trace("CONNECT STD %s %d", addr, port);
                    s.connect(new InternetAddress(addr, port));
                }
                catch (Exception e)
                {
                    Thread.sleep(dur!("seconds")(3));
                    continue;
                }
                break;
            }
            log.trace("CONNECTED STD");
        }
    }


    public RequestResponse put(bool need_auth, string user_uri, string[] individuals)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			log.trace("ERR! connector.put, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);			
			return request_response;
		}	
		if (individuals.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			log.trace("ERR! connector.put, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);						
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
            version (WebServer)
            {
                s.write(buf);
            }
            version (std_socket)
            {
                s.send(buf);
            }

            version (WebServer)
            {
                buf.length = 4;
                s.read(buf);
                long receive_size = buf.length;
            }

            version (std_socket)
            {
                buf.length = 4;
                long receive_size = s.receive(buf);
            }
            //stderr.writeln("RECEIVE SIZE BUF ", receive_size);


            //stderr.writeln("RESPONSE SIZE BUF ", buf);
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];
            //stderr.writeln("RESPONSE SIZE ", response_size);
            response = new ubyte[ response_size ];

            version (WebServer)
            {
                s.read(response);
                receive_size = response.length;
            }
            version (std_socket)
            {
                receive_size = s.receive(response);
            }
            //stderr.writeln("RECEIVE RESPONSE ", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                log.trace("@RECONNECT PUT REQUEST");
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
            log.trace("@ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public RequestResponse get(bool need_auth, string user_uri, string[] uris, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			log.trace("ERR! connector.get, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);			
			return request_response;
		}	
		if (uris.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			log.trace("ERR! connector.get, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            log.trace("connector.get PACK GET REQUEST need_auth=%b, user_uri=%s, uris=%s", need_auth, user_uri, uris);

        packer.beginArray(uris.length + 3);
        packer.pack(INDV_OP.GET, need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        log.trace("connector.get DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            version (WebServer)
            {
                s.write(buf);
            }
            version (std_socket)
            {
                s.send(buf);
            }

	        if (trace)
		        log.trace("connector.get SEND %s", buf);


            version (WebServer)
            {
                buf.length = 4;
                s.read(buf);
                long receive_size = buf.length;
            }

            version (std_socket)
            {
                buf.length = 4;
                long receive_size = s.receive(buf);
            }
            
            if (trace)
                log.trace("connector.get RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                log.trace("connector.get RESPONSE SIZE BUF %s", buf);
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                log.trace("connector.get RESPONSE SIZE %d", response_size);

            response = new ubyte[ response_size ];

            version (WebServer)
            {
                s.read(response);
                receive_size = response.length;
            }
            version (std_socket)
            {
                receive_size = s.receive(response);
            }
            if (trace)
                log.trace("connector.get RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                log.trace ("connector.get @RECONNECT GET REQUEST");
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
                log.trace("connector.get OP RESULT = %d", obj.via.uinteger);
                
            for (int i = 1, j = 0; i < unpacker.unpacked.length; i += 2, j++)
            {
                obj                         = unpacker.unpacked[ i ];
                request_response.op_rc[ j ] = cast(ResultCode)obj.via.uinteger;
                if (request_response.op_rc[ j ] == ResultCode.OK)
                    request_response.msgpacks[ j ] = cast(string)unpacker.unpacked[ i + 1 ].via.raw;
                if (trace)
                    log.trace("connector.get GET RESULT = %d", obj.via.uinteger);
            }
        }
        else
            log.trace("connector.get @ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    public RequestResponse remove(bool need_auth, string user_uri, string[] uris, bool trace)
    {
        ubyte[]         response;
        RequestResponse request_response = new RequestResponse();

		if (user_uri is null || user_uri.length < 3)
		{
			request_response.common_rc = ResultCode.Not_Authorized;
			log.trace("ERR! connector.remove, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);			
			return request_response;
		}	
		if (uris.length == 0)
		{
			request_response.common_rc = ResultCode.No_Content;
			log.trace("ERR! connector.remove, code=%s", request_response.common_rc);
			printPrettyTrace(stderr);			
			return request_response;
		}	

        Packer          packer           = Packer(false);

		//need_auth = false;

        if (trace)
            log.trace("connector.get PACK REMOVE REQUEST need_auth=%b, user_uri=%s, uris=%s", need_auth, user_uri, uris);

        packer.beginArray(uris.length + 3);
        packer.pack(INDV_OP.REMOVE, need_auth, user_uri);
        for (int i = 0; i < uris.length; i++)
            packer.pack(uris[ i ]);

        long request_size = packer.stream.data.length;

        if (trace)
	        log.trace("connector.remove DATA SIZE %d", request_size);

        buf = new ubyte[ 4 + request_size ];

        buf[ 0 ]               = cast(byte)((request_size >> 24) & 0xFF);
        buf[ 1 ]               = cast(byte)((request_size >> 16) & 0xFF);
        buf[ 2 ]               = cast(byte)((request_size >> 8) & 0xFF);
        buf[ 3 ]               = cast(byte)(request_size & 0xFF);
        buf[ 4 .. buf.length ] = packer.stream.data;

        for (;; )
        {
            version (WebServer)
            {
                s.write(buf);
            }
            version (std_socket)
            {
                s.send(buf);
            }

	        if (trace)
		        log.trace("connector.remove SEND %s", buf);


            version (WebServer)
            {
                buf.length = 4;
                s.read(buf);
                long receive_size = buf.length;
            }

            version (std_socket)
            {
                buf.length = 4;
                long receive_size = s.receive(buf);
            }
            
            if (trace)
                log.trace("connector.remove RECEIVE SIZE BUF %d", receive_size);

            if (trace)
                log.trace("connector.remove RESPONSE SIZE BUF %s", buf);
                
            long response_size = 0;
            for (int i = 0; i < 4; i++)
                response_size = (response_size << 8) + buf[ i ];

            if (trace)
                log.trace("connector.remove RESPONSE SIZE %d", response_size);

            response = new ubyte[ response_size ];

            version (WebServer)
            {
                s.read(response);
                receive_size = response.length;
            }
            version (std_socket)
            {
                receive_size = s.receive(response);
            }
            if (trace)
                log.trace("connector.remove RECEIVE RESPONSE %s", receive_size);

            if (receive_size == 0 || receive_size < response.length)
            {
                Thread.sleep(dur!("seconds")(1));
                log.trace ("connector.remove @RECONNECT REMOVE REQUEST");
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
                log.trace("connector.remove OP RESULT = %d", obj.via.uinteger);
                
            for (int i = 1; i < unpacker.unpacked.length; i++)
            {
                obj                             = unpacker.unpacked[ i ];
                request_response.op_rc[ i - 1 ] = cast(ResultCode)obj.via.uinteger;
            }
        }
        else
            log.trace("connector.remove @ERR ON UNPACKING RESPONSE");

        return request_response;
    }

    void close()
    {
        s.close();
    }
}