#!/usr/bin/env tarantool
box.cfg{listen=3308, slab_alloc_arena=5.0, slab_alloc_maximal=67108864}
box.schema.space.create('subjects', {engine='vinyl'})
box.space.subjects:create_index('primary', {parts={1, 'string'}})
box.schema.user.grant('guest', 'read,write', 'space', 'subjects')
box.schema.space.create('cache')
box.space.cache:create_index('primary', {parts={1, 'string'}, type='hash'})
box.schema.user.grant('guest', 'read,write', 'space', 'cache')
require("test_auth")