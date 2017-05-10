box.cfg{listen=3309, work_dir='./data/tarantool', log_level=5, log='./tarantool.log', memtx_memory=268435456.0}
log = require('log')

if box.space.individuals == nil then
    box.schema.space.create('individuals', {engine='vinyl'})
    -- box.schema.space.create('individuals')
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'individuals')
end

if box.space.rdf_types == nil then
    box.schema.space.create('rdf_types', {engine='vinyl'})
    -- box.schema.space.create('rdf_types')
    box.space.rdf_types:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'rdf_types')
end

if box.space.permissions == nil then
    box.schema.space.create('permissions', {engine='vinyl'})
    -- box.schema.space.create('permissions')
    box.space.permissions:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'permissions')
end

if box.space.memberships == nil then
    box.schema.space.create('memberships', {engine='vinyl'})
    -- box.schema.space.create('memberships')
    box.space.memberships:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'memberships')
end


socket = require('socket')
require('db_handler')
msgpack = require('msgpack')

function handle_request(s) 
    --  print('connect nonblock=')
    --  print(s:nonblock())
    s:nonblock(true)
    while true do
--        log.info('start loop')
        local size_str, size, op, op_str, msg, resp, resp_size
        local resp_size_str, msg_table, zero_count, zero_pos
        local peer_info

--        log.info('#1 s=%s', s)
        local res= s:readable()
--        log.info('#2 res=%s', res)
        -- peer_info = s:peer()
--        log.info('START')
        size_str = s:read(4)
        if size_str == nil or size_str == "" or string.len(size_str) < 4 then
            log.info('BREAK: size_str == nil or size_str == "" or string.len(size_str) < 4, size_str=[%s]', size_str)
            break
        end

        size  = 0
        for i=1, 4, 1 do
            size = bit.lshift(size, 8) + string.byte(size_str, i)
        end
--        log.info('size=%d', size)
        
        --[[op_str = s:read(1)
        if op_str == "" or op_str == nil then
            log.info('BREAK ')
            break
        end
        log.info('#1')
        op = string.byte(op_str, 1)
        log.info('op=%d', op)]]
        
        msg = s:read(size)
        if msg == nil or msg == "" or string.len(msg) < size then
            log.info('BREAK: msg == nil or msg == "" or string.len(msg) < size, msg=[%s]', msg)
            break
        end
        
--        log.info('lua msg=[%s]', msg)
        resp = db_handle_request(msg);
        -- log.info(resp);
        resp_size = string.len(resp)
--        log.info('resp_len=%d', resp_size)
--        log.info('resp=[%s]', resp)
        -- obj = msgpack.decode(resp)
        -- print("obj ".. obj)
        resp_size_str = string.char(bit.band(bit.rshift(resp_size, 24), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 16), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 8), 255)) ..
            string.char(bit.band(resp_size, 255))
--        log.info('resp_size_str=[%d][%d][%d][%d]', bit.band(bit.rshift(resp_size, 24), 255), bit.band(bit.rshift(resp_size, 16), 255), bit.band(bit.rshift(resp_size, 8), 255), bit.band(resp_size, 255))
         s:send(resp_size_str..resp)
--         s:send(resp)
--        log.info('END')
    end
end

socket.tcp_server('0.0.0.0', 9999, handle_request)    
print('ready')
