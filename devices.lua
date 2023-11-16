
local _M={}

_M.aplayCommand = "aplay -l"
_M.commandOutput={}
_M.online = {}
_M.currentDevice = {}
_M.deviceRegex = "^card (%d+): .- %[(.-)%], device (%d+): (.+)$"

-- Initializes the device state with first sync
function _M:init()
	self:sync()
end

-- Parse the output and extract device information
function _M:sync()

	self:refresh()

	for line in self.commandOutput:gmatch("[^\r\n]+") do
    	local card, name, device = line:match(self.deviceRegex)

    	if card and device and name then
        	self.currentDevice.card = tonumber(card)
        	self.currentDevice.name = name
        	self.currentDevice.device = device
        	table.insert(self.online, self.currentDevice)
        	self.currentDevice = {}
    	end
	end
end

-- Function to execute a shell command and return the output
function _M:refresh()
    local handle = io.popen(self.aplayCommand)
	self.commandOutput = handle:read("*a")
    handle:close()
	--print("commandOutput:", self.commandOutput)
end

function _M:dump()
	-- Print the list of devices
	for i, device in ipairs(self.online) do
	    print("Card:", device.card, " Device: ", device.device, " Name: ", device.name)
	end
end

return _M
