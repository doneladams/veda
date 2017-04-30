box.cfg{listen=3309, work_dir='./data/tarantool', log_level=5, logger='./tarantool.log', memtx_memory=268435456.0}
log = require('log')

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
ffi = require('ffi')
db_handler = ffi.load('./libdb_handler.so')
ffi.cdef('struct Response {char *msg; int size;};')
-- ffi.cdef('struct Response handle_request(char *msg, size_t msg_size)')
ffi.cdef('void handle_request(char *msg, size_t msg_size, int fd)')
ffi.cdef('void free(void *)')

function handle_request(s) 
    s:nonblock(true)
    while true do
--        log.info('start loop')
        local size_str, size, op, op_str, msg, resp
        local resp_size_str, resp_str
        local peer_info
        local c_str

--        log.info('#1 s=%s', s)
        local res= s:readable()
--        log.info('#2 res=%s', res)
        peer_info = s:peer()
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
        -- resp = db_handle_request(msg);
        c_str=ffi.new("char[?]", size)
        ffi.copy(c_str, msg)
        -- resp = db_handler.handle_request(c_str, size)
        db_handler.handle_request(c_str, size, s:fd())
        --[[log.info('resp=[%s]', resp)
        log.info('resp.size=[%d]', resp.size)
        log.info('resp.msg=[%s]', ffi.string(resp.msg, resp.size));]]

        --[[resp_size_str = string.char(bit.band(bit.rshift(resp.size, 24), 255)) ..
            string.char(bit.band(bit.rshift(resp.size, 16), 255)) ..
            string.char(bit.band(bit.rshift(resp.size, 8), 255)) ..
            string.char(bit.band(resp.size, 255))]]
        -- log.info('resp_size_str=[%d][%d][%d][%d]', bit.band(bit.rshift(resp_size, 24), 255), bit.band(bit.rshift(resp_size, 16), 255), bit.band(bit.rshift(resp_size, 8), 255), bit.band(resp_size, 255))
        --  s:send(resp_size_str..resp)
        
        --[[resp_str = ffi.string(resp.msg, resp.size)
        s:send(resp_size_str..resp_str)
        ffi.C.free(resp.msg); ]]       
--        log.info('END')
    end
end

socket.tcp_server('0.0.0.0', 9999, handle_request)    
print('ready')