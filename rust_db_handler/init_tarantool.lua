box.cfg{listen=3309, work_dir='./data/tarantool', log_level=5, log='./tarantool.log', memtx_memory=268435456.0}
log = require('log')

memtx = true

if box.space.individuals == nil then
    if memtx then
        box.schema.space.create('individuals')
    else
        box.schema.space.create('individuals', {engine='vinyl'})
    end    
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'individuals')
end

if box.space.rdf_types == nil then
    if memtx then
        box.schema.space.create('rdf_types')
    else 
        box.schema.space.create('rdf_types', {engine='vinyl'})
    end
    box.space.rdf_types:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'rdf_types')
end

if box.space.permissions == nil then
    if memtx then 
        box.schema.space.create('permissions')
    else 
        box.schema.space.create('permissions', {engine='vinyl'})
    end
    box.space.permissions:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'permissions')
end

if box.space.memberships == nil then
    if memtx then
        box.schema.space.create('memberships')
    else
        box.schema.space.create('memberships', {engine='vinyl'})
    end        
    box.space.memberships:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'memberships')
end

if box.space.logins == nil then
    if memtx then
        box.schema.space.create('logins')
    else
        box.schema.space.create('logins', {engine='vinyl'})
    end        
    box.space.logins:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'logins')
end

if box.space.tickets == nil then
    if memtx then
        box.schema.space.create('tickets')
    else
        box.schema.space.create('tickets', {engine='vinyl'})
    end
    box.space.tickets:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'tickets')
end

socket = require('socket')
require('db_handler')
msgpack = require('msgpack')

function handle_request(s) 
    local n = 0
    s:nonblock(true)
    while true do
        local size_str, size, op, op_str, msg, resp, resp_size
        local resp_size_str, msg_table, zero_count, zero_pos
        local peer_info

        local res= s:readable()
        size_str = s:read(4)
        if size_str == nil or size_str == "" or string.len(size_str) < 4 then
            log.info('BREAK: size_str == nil or size_str == "" or string.len(size_str) < 4, size_str=[%s]', size_str)
            break
        end

        size  = 0
        for i=1, 4, 1 do
            size = bit.lshift(size, 8) + string.byte(size_str, i)
        end
        
        msg = s:read(size)
        if msg == nil or msg == "" or string.len(msg) < size then
            log.info('BREAK: msg == nil or msg == "" or string.len(msg) < size, msg=[%s]', msg)
            break
        end
        
        resp = db_handle_request(msg);
        resp_size = string.len(resp)
        resp_size_str = string.char(bit.band(bit.rshift(resp_size, 24), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 16), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 8), 255)) ..
            string.char(bit.band(resp_size, 255))
        s:send(resp_size_str..resp)
        n = n + 1
    end
end

socket.tcp_server('0.0.0.0', 9999, handle_request)    
print('ready')
