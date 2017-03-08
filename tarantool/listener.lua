local listener = {}

function listener.start()
  --  net_box = require('net.box')
   -- connection = net_box:new(3308)
    -- require("c_listener")
    require("golistener")
    golistener_start();
end
return listener



