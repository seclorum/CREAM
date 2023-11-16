
require ("config")
require ("util/environment_debug")
require ("util/lua_enumerable")
require ("util/filesystem")

dateparse =  require("util/dateparse")

local _M = {}

_M.devices=require("devices")
_M.mixer=require("mixer")

_M.edit = {}
_M.edit.Clips = {}

function _M:init()
	_M:updateWAVlist()
end

function _M:updateWAVlist()
	_M.edit.Clips = scandirForWAV(CREAM_ARCHIVE_DIRECTORY)
	_M.edit.Tracks = {}
	for i,v in ipairs(_M.edit.Clips) do
		table.insert(_M.edit.Tracks, v)
	end
end

function _M:update()
	_M:updateWAVlist()
	return true
end

return _M
