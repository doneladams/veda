box.cfg{listen=3309, slab_alloc_arena=10.0, slab_alloc_maximal=67108864}
socket = require('socket')
aclserver = require('aclserver')

socket.tcp_server('0.0.0.0', 3303, function(s)
        local size, op, msg, resp, resp_size, resp_size_str
        size  = 0
        for i=1, 4, 1 do
            size = bit.lshift(size, 8) + string.byte(s:read(1))
        end
        print('size='..size)
        
        op = string.byte(s:read(1))
        print('op='..op)
        
        msg = s:read(size)
        print('msg='..msg)
        resp = aclserver_start(op, msg)
        resp_size = string.len(resp)
        print('resp_len='..resp_size)
        print('resp='..resp)
        resp_size_str = string.char(bit.band(bit.rshift(resp_size, 24), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 16), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 8), 255)) ..
            string.char(bit.band(resp_size, 255))
        print('resp_size_str='..resp_size_str)
        s:send(resp_size_str)
        s:send(resp)

    end)