box.cfg{listen=3309, work_dir='./data/tarantool', slab_alloc_arena=10.0, slab_alloc_maximal=67108864}
if box.space.individuals == nil then
    box.schema.space.create('individuals', {engine='vinyl'})
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'individuals')
end

if box.space.rdf_types == nil then
    box.schema.space.create('rdf_types', {engine='vinyl'})
    box.space.rdf_types:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'rdf_types')
end

if box.space.acl == nil then
    box.schema.space.create('acl', {engine='vinyl'})
    box.space.acl:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'acl')
end
if box.space.acl_cache == nil then
    box.schema.space.create('acl_cache')
    box.space.acl_cache:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'acl_cache')
end

socket = require('socket')
require('db_handler')
msgpack = require('msgpack')

socket.tcp_server('0.0.0.0', 9999, function(s)
        local size, op, msg, resp, resp_size, resp_size_str, msg_table, zero_count, zero_pos
        size  = 0
        for i=1, 4, 1 do
            size = bit.lshift(size, 8) + string.byte(s:read(1))
        end
        -- print('size='..size)
        
        op = string.byte(s:read(1))
        -- print('op='..op)
        
        msg = s:read(size)
        print("lua msg="..msg)
        resp = db_handle_request(op, msg);
        resp_size = string.len(resp)
        print('resp_len='..resp_size)
        print('resp='..resp)
        -- obj = msgpack.decode(resp)
        -- print("obj ".. obj)
        resp_size_str = string.char(bit.band(bit.rshift(resp_size, 24), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 16), 255)) ..
            string.char(bit.band(bit.rshift(resp_size, 8), 255)) ..
            string.char(bit.band(resp_size, 255))
        print('resp_size_str='..resp_size_str)
        s:send(resp_size_str)
        s:send(resp)
    end)    