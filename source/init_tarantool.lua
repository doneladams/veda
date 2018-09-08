box.cfg{listen=3309, work_dir='./data/tarantool', log_level=5, log='./tarantool.log', memtx_memory=268435456.0, readahead = 10 * 1024 * 1024}
log = require('log')

memtx = false

if box.space.INDIVIDUALS == nil then

    box.schema.sequence.create('G1',{min=1, start=1})

    if memtx then
        space = box.schema.space.create('INDIVIDUALS')
    else
        space = box.schema.space.create('INDIVIDUALS', {engine='vinyl'})
    end

    print ('space.individuals:', space.id, '\n')

--    box.space.INDIVIDUALS:create_index('primary', {parts={1, 'string'}})
    box.space.INDIVIDUALS:create_index('primary', {parts={1, 'unsigned'}, sequence='G1'})
    box.space.INDIVIDUALS:create_index('S', {type = 'tree', unique = false, parts = {2, 'string'}})
    box.space.INDIVIDUALS:create_index('P', {type = 'tree', unique = false, parts = {3, 'string'}})
    box.space.INDIVIDUALS:create_index('O', {type = 'tree', unique = false, parts = {4, 'string'}})
    box.space.INDIVIDUALS:create_index('SP', {type = 'tree', unique = false, parts = {2, 'string', 3, 'string'}})
    box.space.INDIVIDUALS:create_index('PO', {type = 'tree', unique = false, parts = {3, 'string', 4, 'string'}})
    box.space.INDIVIDUALS:create_index('SO', {type = 'tree', unique = false, parts = {2, 'string', 4, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'INDIVIDUALS')
    box.schema.user.grant('guest', 'read,write', 'universe')

    box.schema.user.create('veda6', {password = '123456'}, {if_not_exists = false})
    box.schema.user.grant('veda6', 'read,write,execute', 'universe')
end

if box.space.TICKETS == nil then
    if memtx then
        space = box.schema.space.create('TICKETS')
    else
        space = box.schema.space.create('TICKETS', {engine='vinyl'})
    end

    print ('space.tickets:', space.id, '\n')

--    box.space.TICKETS:create_index('primary', {parts={1, 'string'}})
    box.space.TICKETS:create_index('primary', {parts={1, 'unsigned'}, sequence='G1'})
    box.space.TICKETS:create_index('S', {type = 'tree', unique = false, parts = {2, 'string'}})
    box.space.TICKETS:create_index('P', {type = 'tree', unique = false, parts = {3, 'string'}})
    box.space.TICKETS:create_index('O', {type = 'tree', unique = false, parts = {4, 'string'}})
    box.space.TICKETS:create_index('SP', {type = 'tree', unique = false, parts = {2, 'string', 3, 'string'}})
    box.space.TICKETS:create_index('PO', {type = 'tree', unique = false, parts = {3, 'string', 4, 'string'}})
    box.space.TICKETS:create_index('SO', {type = 'tree', unique = false, parts = {2, 'string', 4, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'TICKETS')
end

print('ready\n')
