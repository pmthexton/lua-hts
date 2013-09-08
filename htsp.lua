local ls = require "lsocket"
local crypto = require "crypto"
local htsmsg = require "htsmsg"
local struct = require "struct"

local HTSP_PROTO_VERSION = 6

local htsp = {}
htsp.__index = htsp


-- This adds a metatable to the htsp table which makes it a callable table.
-- This is purely a style choice, it allows us to create htsp instances in
-- a manner similar to C++/Java constructor calls.
setmetatable(htsp,{
	__call = function(cls,...)
		return cls.new(...)
	end,
})

-- support function, turn hex string rep in to actual binary data
function fromhex(s)
	return (s:gsub('..',function(cc) return string.char(tonumber(cc,16)) end))
end

function htsp:connect()
	self._socket,err = ls.connect(self.opts.host,self.opts.port)
	if not self._socket
	then
		error(err)
	end
	ls.select(nil,{self._socket},2000)
end

function htsp:authenticate()
	if self.challenge ~= nil and self.opts.pass ~= nil
	then
		self.digest = function() return fromhex(crypto.digest("sha1",self.opts.pass..self.challenge)) end
	end
	self:send({method="authenticate"})
end

function htsp:recv(option)
	local ignoreQueue = option or false
	-- return any previously received asynchronous messages first unless told not to
	if ignoreQueue == false and #self.queue > 0
	then
		return table.remove(self.queue,1)
	end

	local sel=ls.select({self._socket},2000)
	if type(sel)=="table"
	then
		local respsize=self._socket:recv(4)
		if respsize:len() ~= 4
		then
			error("error reading from socket, could not read initial length bytes")
		end
		local respint = struct.unpack('>I4',respsize)
		if respint > 0
		then
			-- read the response in as many chunks as required. string concat in lua can be
			-- slow, so store the individual chunks in a table (quicker) for concatenation when
			-- finished reading
			local respbody = ""
			local resptable = {}
			local bytesread = 0
			while bytesread < respint
			do
				local sel=ls.select({self._socket},2000)
				if type(sel) == "table"
				then
					local temp = self._socket:recv(respint-bytesread)
					bytesread = bytesread + temp:len()
					table.insert(resptable,temp)
				else
					error("Comms problem - timed out waiting for data chunk from TVHeadend")
				end
			end
			respbody = table.concat(resptable)
			local response = htsmsg.deserialize(respsize..respbody)
			return response
		else
			return {}
		end
	else
		error("Timed out waiting for response")
	end
end

function htsp:send(t)
	if self.opts.user ~= nil then t.username=self.opts.user end
	if self.digest ~= nil then t.digest=self.digest end
	self.seq = self.seq + 1
	t.seq = self.seq

	local msg = htsmsg.serialize(t)

	if self._socket
	then
		local sent,err = self._socket:send(msg)
		if not sent or sent < msg:len()
		then
			error("error sending, bytes sent["..tostring(sent).."],err="..err)
		end
		local resp = {}
		while resp.seq == nil or resp.seq ~= t.seq
		do
			resp = self:recv(true)
			if resp.seq ~= t.seq
			then
				table.insert(self.queue,resp)
			end
		end
		return resp
	else
		error("Not connected to TVHeadend")
	end
end


function htsp:init(opts)
	self.opts=opts
	self.seq=0
	self.queue={}
end

function htsp:hello()
	self:send({method="hello",htspversion=HTSP_PROTO_VERSION,clientname="LuaClient"})
end

function htsp:enableAsyncMetadata()
	self:send({method="enableAsyncMetadata"})
end

function htsp.new(_opts)
	local o = {}
	local opts = _opts or {}
	if not opts.host then opts.host = "127.0.0.1" end
	if not opts.port then opts.port = 9982 end
	setmetatable(o,htsp)
	o:init(opts)
	return o
end

return htsp
