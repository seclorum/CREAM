local _M={}

local lgi=require("lgi")
local GLib = lgi.GLib
local Gst = lgi.Gst

if Gst.Parse ~= nil then
	_M.play = Gst.Parse.launch('alsasrc ! audioconvert ! wavenc ! filesink location=/tmp/permanent.wav')
else
	print("No Parse interface..")
end

function _M:init()
	--self.play.uri = 'http://ice1.somafm.com/dronezone-128-mp3'
	--self.play.uri = "file:///home/mix/Recordings/default_norm.wav"
	self.play.bus:add_watch(GLib.PRIORITY_DEFAULT, self.bus_callback)
	self.play.state = 'PLAYING'
	self.main_loop = GLib.MainLoop()
end


function _M:bus_callback(bus, message)

	if (message ~= nil) then
		if message.type.ERROR then
      		print('Error:', message:parse_error().message)
      		self.main_loop:quit()
   		elseif message.type.EOS then
      		print 'end of stream'
      		self.main_loop:quit()
   		elseif message.type.STATE_CHANGED then
      		local old, new, pending = message:parse_state_changed()
      		print(string.format('state changed: %s->%s:%s', old, new, pending))
   		elseif message.type.TAG then
      		message:parse_tag():foreach(
	 		function(list, tag)
	    		print(('tag: %s = %s'):format(tag, tostring(list:get(tag))))
	 		end)
   		end
	end

   return true
end

-- Run the loop.
function _M:run()
	self.main_loop:run()
end

function _M:stop()
	self.play.state = 'NULL'
	self.main_loop:stop()
end

return _M
