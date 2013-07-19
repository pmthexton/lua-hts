lua-hts
=======

Simple htsp client module and sample application for Lua

The implementation here depends on your lua installation having the following
modules available:
	lsocket - http://www.tset.de/lsocket/
	struct - http://www.inf.puc-rio.br/~roberto/struct/

Note: You may notice when receiving binary fields in a message from tvheadend that the field value
is actually a function. This is simply because lua has no native type suitable for storing
the data in which is distinguishable from a printable string.

The easiest way I could see out of the hole was to store the data inside a callable function,
call the function and it will return the 'binary' data as a string for you to operate on as
appropriate.

Also, if you wish to send binary data to tvheadend you need to wrap it up in the same way,
see the authenticate function in htsp.lua for an example, this creates an auth appropriate 
auth token and converts it from a hex string to binary data then stores this in a function
which is then later dealt with correctly when passed in to htsmsg.serialize as a table item.
