
require ("config")
require ("util/environment_debug")
require ("util/lua_enumerable")
require ("util/filesystem")

dateparse =  require("util/dateparse")

local _M = {}

_M.devices=require("devices")
_M.mixer=require("mixer")

_M.data = {}
_M.data.wavFiles = {}

function _M:init()
	_M:updateWAVlist()
end

function _M:updateWAVlist()
	_M.data.wavFiles = scandirForWAV(CREAM_ARCHIVE_DIRECTORY)
	_M.data.URLs = {}
	for i,v in ipairs(_M.data.wavFiles) do
		table.insert(_M.data.URLs, v)
	end
end

function _M:update()
	_M:updateWAVlist()
	return true
end

return _M
