local struct = require "struct"

local MAP = 1
local S64 = 2
local STR = 3
local BIN = 4
local LIST = 5

-- forward declarations
local decoders = {}
local encoders = {}

-- support function, determine the number of bytes required for integer 'n' as (log2(n)/8)+1
local function bytesneeded(n)
	return math.floor((math.log(n)/math.log(2))/8)+1
end

-- support function - add the contents of 'toadd' to 'dest' by key
local merge = function(dest,toadd)
	for k,v in pairs(toadd)
	do
		dest[k]=v
	end
end

-- support function - determine the msgType of the element in 'data' at 'index', call the relevant handler
-- and return the value and new working index 
local parseEl = function(data,index)
	local value
	local msgType,index = struct.unpack('I1',data,index)
	value,index = decoders[msgType].fn(data,index)
	return value,index
end

-- Section for decoders
decoders[MAP] = {["desc"]="MAP",["fn"]=function(data,index)
		local namelen,valuelen,name,value,offset
		local map={}
		namelen,valuelen,index = struct.unpack('I1>I4',data,index)
		if namelen > 0
		then
			name,index = struct.unpack('c'..tostring(namelen),data,index)
		end
		-- store the offset so we can make sure we don't loop too far
		-- through the serialised data 
		offset = index
		while type(index) == "number" and index < valuelen+offset
		do
			temp,index = parseEl(data,index)
			merge(map,temp)
		end
		-- if we have no name, then this data was part of a list, return an
		-- appropriately constructed response
		if name ~= nil
		then
			return {[name]=map},index
		else
			return map,index
		end
	end -- end function
	}
decoders[S64] = {["desc"]="S64",["fn"]=function(data,index)
		local namelen,valuelen,name,value
		namelen,valuelen,index = struct.unpack('I1>I4',data,index)

		-- Unpack the name and value seperately, this allows us to accomodate
		-- values that are part of a list where no name is present. the luastruct
		-- module doesn't like it when we specify a zero length char so we can't
		-- do it in one shot

		if namelen > 0
		then
			name,index = struct.unpack('c' .. tostring(namelen),data,index)
		end
		if valuelen > 0
		then
			value,index = struct.unpack('>I' .. tostring(valuelen),data,index)
		end

		-- if we have no name, then this data was part of a list, return an
		-- appropriately constructed response
		if name ~= nil
		then
			return {[name]=value},index
		else
			return value,index
		end
	end -- end function
	}
decoders[STR] = {["desc"]="STR",["fn"]=function(data,index)
		local namelen,valuelen,name,value
		namelen,valuelen,index = struct.unpack('I1>I4',data,index)
		-- Unpack the name and value seperately, this allows us to accomodate
		-- values that are part of a list where no name is present. the luastruct
		-- module doesn't like it when we specify a zero length char so we can't
		-- do it in one shot

		if namelen > 0
		then
			name,index = struct.unpack('c' .. tostring(namelen),data,index)
		end
		if valuelen > 0
		then
			value,index = struct.unpack('c' .. tostring(valuelen),data,index)
		end

		-- if we have no name, then this data was part of a list, return an
		-- appropriately constructed response
		if name ~= nil
		then
			return {[name]=value},index
		else
			return value,index
		end
	end -- end function
	}
decoders[BIN] = {["desc"]="BIN",["fn"]=function(data,index)
		local namelen,valuelen,name,value
		-- This may look a little odd, but we need to distinguish between the data
		-- types (to be able to reconstruct the message more than anything)
		-- and the loose type definitions in lua are not helpful here. As a solution we
		-- store the answer as a callable function which returns the raw data as a get-out
		namelen,valuelen,index = struct.unpack('I1>I4',data,index)
		if namelen>0 and valuelen>0
		then
			name,value,index = struct.unpack('c'..tostring(namelen)..'c'..tostring(valuelen),data,index)
		else
			error("Invalid packet format detected at position" .. tostring(index-1))
		end
		return {[name]=function() return value end},index
	end -- end function
	}
decoders[LIST] = {["desc"]="LIST",["fn"]=function(data,index)
		local namelen,valuelen,name,value,offset
		local list={}
		namelen,valuelen,index = struct.unpack('I1>I4',data,index)
		name,index = struct.unpack('c'..tostring(namelen),data,index)
		-- store the offset so we can make sure we don't loop too far
		-- through the serialised data 
		offset = index
		while type(index)=="number" and index < valuelen+offset
		do
			temp,index = parseEl(data,index)
			table.insert(list,temp)
		end
		return {[name]=list},index
	end -- end function
	}

-- section for encoders
encoders["function"] = function(i,v)
	local data
	data = struct.pack("I1I1>I4c" .. tostring(i:len()) .. "c" .. tostring(v():len()), 4, i:len(), v():len(), i, v())
	return data
end
encoders["htslist"] = function(t)
	local data = ""
	for i=1,#t,1
	do
		if(encoders[type(t[i])])
		then
			data = data .. encoders[type(t[i])]("",t[i])
		else
			abort()
		end
	end
	return data
end
encoders["htsmap"] = function(t)
	local data = ""
	for i,v in pairs(t)
	do
		data = data .. encoders[type(v)](i,v)
	end
	return data
end
encoders["string"] = function(i,v)
	local data
	-- if the name length is 0 then we're adding to a list
	if i:len()>0
	then
		data = struct.pack('I1I1>I4c'..tostring(i:len())..'c'..tostring(v:len()),STR,i:len(),v:len(),i,v)
	else
		data = struct.pack('I1I1>I4c'..tostring(v:len()),STR,0,v:len(),v)
	end
	return data
end
encoders["number"] = function(i,v)
	local data
	-- if the name length is 0 then we're adding to a list
	if i:len()>0
	then
		data = struct.pack('I1I1>I4c'..tostring(i:len())..'>I'..tostring(bytesneeded(v)),S64,i:len(),bytesneeded(v),i,v)
	else
		data = struct.pack('I1I1>I4>I'..tostring(bytesneeded(v)),S64,0,bytesneeded(v),v)
	end
	return data
end
encoders["table"] = function(i,v)
	local data
	local msgType
	if #v > 0
	then
		msgType = LIST
		data = encoders["htslist"](v)
	else
		msgType = MAP
		data = encoders["htsmap"](v)
	end
	data = struct.pack("I1I1>I4c" .. tostring(i:len()) .. "c" .. tostring(data:len()), msgType, i:len(), data:len(), i, data)
	return data
end


--use of module is deprecated!
--module(...)

local htsmsg = {}

htsmsg.asString = function(t,depth)
	local t = t
	local depth = depth or 0
	local num = 0
	local temp = {}

	local print = function(...)
		--oldprint(string.rep("\t",depth) .. ...)
		table.insert( temp, string.rep("\t",depth))
		table.insert( temp, ...)
		table.insert( temp, "\n")
	end

	local function toHex(s)
		return (string.gsub(s,"(.)",function(c)
			return string.format("%02X",string.byte(c))
		end))
	end

	if depth == 0
	then
		print("{")
	end

	depth = depth + 1

	for i,v in pairs(t)
	do
		if type(v) == "table"
		then
			print( ((num > 0) and "," or "") .. "[\"" .. i .. "\"] = { \n" .. htsmsg.asString(v,depth))
			if depth > 0
			then
				print "}"
			end
		elseif type(v) == "function"
		then
			print( ((num > 0) and "," or "") .. "[\"" .. i .. "\"] = " .. "\"bin:" .. toHex(v()) .. "\"")
		elseif type(v) == "string"
		then
			print( ((num > 0) and "," or "") .. "[\"".. i .. "\"] = " .. "\"" .. v .. "\"")
		else
			print( ((num > 0) and "," or "") .. "[\"".. i .. "\"] = " .. v)
		end
		num = num + 1
	end
	depth = depth - 1

	if depth == 0
	then
		print ("}")
	end

	--oldprint(table.concat(temp))
	return table.concat(temp)
end

htsmsg.deserialize=function(data)
	local results = {}
	local index = 1
	msgsize,index = struct.unpack('>I4',data,index)
	while type(index) == "number" and index < data:len()
	do
		local temp
		temp,index = parseEl(data,index)
		merge(results,temp)
	end
	return results
end

htsmsg.serialize=function(t)
	local data = ""
	for i,v in pairs(t)
	do
		--if type(v) == "string"
		if encoders[type(v)]
		then
			data = data .. encoders[type(v)](i,v)
		else
			error("No support for " .. i .. " with type["..type(v).."], length=", type(v)=="table" and #v or v)
		end
	end
	data = struct.pack(">I4c0",data:len(),data)
	return data
end

return htsmsg
