local _M = {}
_M.APP_NAME = "cream audio broker"

_M.CREAM_PROTOCOL_VERSION = "1.0"

_M.CREAM_COMMAND_INTERVAL = 200

_M.CREAM_APP_SERVER_HOST = "localhost"
_M.CREAM_APP_SERVER_PORT = arg[1] or 8081
_M.CREAM_APP_VERSION = "{\"Version\":\"1.0\", buildDate: \"" .. require("buildDate") .. "\"}"

_M.CREAM_ARCHIVE_DIRECTORY = "/opt/austrianAudio/var/CREAM/"

_M.CREAM_SYNC_PARTNER = "mix-o"

_M.CREAM_HOST = "localhost"
_M.CREAM_COMMAND_PORT = arg[2] or 8080

_M.CREAM_STATIC_DIRECTORY = "/opt/austrianAudio/var/static/js/"

_M.dump = function()
    print("App name: \"" .. _M.APP_NAME .. 
			"\" Protocol Version: " .. _M.CREAM_PROTOCOL_VERSION .. 
			" CREAM CMD Port: " .. _M.CREAM_COMMAND_PORT .. 
			" CREAM Host: " .. _M.CREAM_APP_SERVER_HOST .. 
			" CREAM Port: " .. _M.CREAM_APP_SERVER_PORT)
end

return _M
