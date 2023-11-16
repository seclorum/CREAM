APP_NAME = "cream audio broker"

CREAM_PROTOCOL_VERSION = "1.0"

CREAM_COMMAND_INTERVAL = 200

CREAM_APP_SERVER_HOST = "localhost"
CREAM_APP_SERVER_PORT = arg[1] or 8081
CREAM_APP_VERSION = "{\"Version\":\"1.0\", buildDate: \"" .. require("buildDate") .. "\"}"

CREAM_ARCHIVE_DIRECTORY = "./archive/"

CREAM_HOST = "localhost"
CREAM_COMMAND_PORT = arg[2] or 8080

function dumpConfig()
    print("App name: \"" .. APP_NAME .. 
			"\" Protocol Version: " .. CREAM_PROTOCOL_VERSION .. 
			" CREAM CMD Port: " .. CREAM_COMMAND_PORT .. 
			" CREAM Host: " .. CREAM_APP_SERVER_HOST .. 
			" CREAM Port: " .. CREAM_APP_SERVER_PORT)
end
