#!/usr/bin/env tarantool
box.cfg{
    listen              = 3301,
    pid_file            = "tarantool.pid",
}

console = require('console')
console.start()