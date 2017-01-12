#!/usr/bin/env tarantool
box.cfg{
    listen              = 3301,
    pid_file            = "tarantool.pid",
}

box.schema.space.create('individuals',{id=999})
box.space.individuals:create_index('primary', {type = 'hash', parts = {1, 'string'}})
box.schema.user.grant('guest','read,write','space','individuals')
box.schema.user.grant('guest','read','space','_space')

box.schema.space.create('aclm',{id=997})
box.space.aclm:create_index('primary', {type = 'hash', parts = {1, 'string'}})
box.schema.user.grant('guest','read,write','space','aclm')

box.schema.space.create('aclp',{id=998})
box.space.aclp:create_index('primary', {type = 'hash', parts = {1, 'string'}})
box.schema.user.grant('guest','read,write','space','aclp')


console = require('console')
console.start()