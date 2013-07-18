#!/usr/bin/lua

htsmsg = require "htsmsg"
htsp = require "htsp"

-- create a table containing connection options.
-- these defaults are commented out which leaves an empty table.
-- with an empty table, the default values for host and port are
-- used and no user authentication is performed.
options = {
	--user = "myuser",
	--pass = "mypass",
	--host = "127.0.0.1", -- defaults to 127.0.0.1
	--port = 9982, -- defaults to 9982
}

conn = htsp(options)
conn:connect() -- connect to server. if connection fails a lua error is raised, so no need to check result
conn:hello() -- negotiate connection with server
conn:authenticate() -- authenticate with tvheadend where appropriate
conn:enableAsyncMetadata() -- enable receivng of asynch meta data, this will cause an inital sync to occur

-- perform main while loop. This sits waiting for messages from tvheadend to come in
-- in this example we simply print out the contents of the message using the helper asString
-- function provide in the htsmsg module
while true
do
  t = conn:recv()
  print(htsmsg.asString(t))
end
