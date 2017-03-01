box.cfg{listen=3309, work_dir='./data', slab_alloc_arena=10.0, slab_alloc_maximal=67108864}
if box.space.individuals == nil then
    box.schema.space.create('individuals', {engine='vinyl'})
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'individuals')
end

--[[if box.space.acl == nil then
    box.schema.space.create('acl', {engine='vinyl'})
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'acl')
end
if box.space.acl_cache == nil then
    box.schema.space.create('acl_cache')
    box.space.individuals:create_index('primary', {parts={1, 'string'}})
    box.schema.user.grant('guest', 'read,write', 'space', 'acl_cache')
end]]

listener= require("listener")
listener.start();