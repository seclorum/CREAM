
require ("config")

local turbo = require "turbo"
local turbo_thread = require "turbo.thread" 
local io = require "io" 
local posix = require "posix"
local syslog = require "posix.syslog"
local signal = require "posix.signal"
local cjson = require "cjson"
local syscall = require "syscall"

local creamRuns = false

io.stdout:setvbuf("no")

CREAM=require("cream")

recordingThread = {}

-- cream LOG function
function cLOG(level, ...)
	syslog.syslog(level, ...)
	print("LOG:" .. level .. " " .. ...)
end


-- cream Command STACK and initialization functions
cSTACK = turbo.structs.deque:new()

cSTACK:append(function()
	dumpConfig()
	syslog.setlogmask(LOG_DEBUG)
	syslog.openlog(APP_NAME, LOG_SYSLOG)
	cLOG(syslog.LOG_INFO, APP_NAME .. " starts with protocol version " .. CREAM_PROTOCOL_VERSION .. " on " .. CREAM_APP_SERVER_HOST .. ":" .. CREAM_APP_SERVER_PORT)
	cLOG(syslog.LOG_INFO, CREAM_APP_VERSION)

 	CREAM.devices:init()
	--CREAM.mixer:init()
	--CREAM.devices:sync()
	CREAM.devices:dump()
	--CREAM.mixer:run()
end)


-- cream Web Handlers
local creamWebStatusHandler = class("creamWebStatusHandler", turbo.web.RequestHandler)
local creamWebStopHandler = class("creamWebStopHandler", turbo.web.RequestHandler)
local creamWebStartHandler = class("creamWebStartHandler", turbo.web.RequestHandler)
local creamWebRecordStartHandler = class("creamWebRecordStartHandler", turbo.web.RequestHandler)
local creamWebRecordStopHandler = class("creamWebRecordStopHandler", turbo.web.RequestHandler)


local responseHTML_A = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>cream audio broker - current state</title>
    <style>
        #json-container {
            font-family: 'Courier New', Courier, monospace;
            white-space: pre-wrap;
            padding: 10px;
            border: 1px solid #ccc;
            background-color: #f9f9f9;
        }

        .string {
            color: green;
        }
        .number {
            color: darkorange;
        }
        .key {
            color: blue;
			font-weight: bold;
        }
        .boolean {
            color: brown;
        }
        .null {
            color: gray;
        }
        .link {
            color: #0066cc; /* Blue color for links */
            text-decoration: underline;
            cursor: pointer;
        }
		.highlight {
			background-color: yellow;
		}

    </style>
</head>
<body>
<div id="function-menu">
<a href="/start">Start Recording</a>
<a href="/stop">Stop Recording</a>
</div>
<div id="json-container"></div>
<script>
var jsonObject = ]]

local responseHTML_B = [[;
// Function to prettify and render JSON object
function prettifyAndRenderJSON(jsonObj, containerId) {
    var container = document.getElementById(containerId);
    var jsonString = JSON.stringify(jsonObj, null, 2); // The third parameter (2) is for indentation

    // Replace special characters with HTML entities to display properly in HTML
    jsonString = jsonString.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    // Use <span> elements with class for styling
    var prettyJson = jsonString.replace(/("(\\u[a-f0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g,
        function (match) {
            var cls = 'number'; // default styling for numbers

            if (/^"/.test(match)) {
                if (/:$/.test(match)) {
                    cls = 'key'; // styling for keys
                } else {
                    cls = 'string'; // styling for strings
                }
            } else if (/true|false/.test(match)) {
                cls = 'boolean'; // styling for booleans
            } else if (/null/.test(match)) {
                cls = 'null'; // styling for null
            }

            return '<span class="' + cls + '">' + match + '</span>';
        });

	 // Convert clickable links in app.data.wavURLs array
    prettyJson = prettyJson.replace(/"wavURLs": \[\s*((?:"[^"]*",?\s*)+)\]/g, function (match, p1) {
        var links = p1.replace(/"([^"]*)"/g, '<span class="link" onclick="openLink(\'$1\')">$1</span>');
        return '"wavURLs": [' + links + ']';
    });

    // Wrap the pretty JSON in a <pre> element
    var preElement = document.createElement("pre");
    preElement.innerHTML = prettyJson;

    // Append the <pre> element to the container
    container.appendChild(preElement);

		var wavURLs = jsonObj.app.data.URLs;

        // Create an HTML table
        var table = document.createElement("table");
        table.border = "1";

        // Create table header
        var headerRow = table.insertRow(0);
        var headerCell = headerRow.insertCell(0);
        headerCell.innerHTML = "Wav Files";

        // Create table rows with links
        for (var i = 0; i < wavURLs.length; i++) {
		   highlight_style = "";
            var row = table.insertRow(i + 1);
            var cell = row.insertCell(0);
			if (jsonObj.app.data.current_recording == wavURLs[i]) {
	            highlight_style = 'style="background-color: red;"'
			}
            cell.innerHTML = '<li' + highlight_style + '>' + 
								'<a class="link" href="' + wavURLs[i] + 
								'" target="_blank">' + wavURLs[i] + '</a>' +
								'<audio controls="controls"><source src="' +
								wavURLs[i] + 
								'" type="audio/x-wav" /></audio>' + 
								'</li>';

        }

        // Append the table to the container
        container.appendChild(table);
}


// Function to open the link (you can customize this based on your server)
function openLink(fileName) {
    alert("Opening link: " + fileName);
    // Replace the alert with logic to open the link on your server
}


// Call the prettifyAndRenderJSON function with your JSON object and the container ID
prettifyAndRenderJSON(jsonObject, "json-container");
function renderJSON(jsonObj, containerId) {
    var container = document.getElementById(containerId);
    var jsonString = JSON.stringify(jsonObj, null, 8); // The third parameter (2) is for indentation
    var preElement = document.createElement("pre");
    preElement.textContent = jsonString;
    container.appendChild(preElement);
}
//renderJSON(jsonObject, "json-container");
</script>
</body>
</html>
]]


function creamWebStatusHandler:get()
	CREAM:update()
	local currentState = responseHTML_A .. 
				cjson.encode({app = {recording = creamRuns, name = APP_NAME, version = CREAM_APP_VERSION, data = CREAM.data, io = { CREAM.devices.online } } }) .. 
			responseHTML_B 
	self:write(currentState)
	self:finish()
end

function creamWebStatusHandler:on_finish()
	collectgarbage("collect")
end


-- Function to execute a shell command and capture its output
function execute_command(command)
    local file = io.popen(command)
    local output = file:read("*a")
    file:close()
    return output
end

-- Coroutine function to execute a shell command asynchronously
local function execute_command_async(command, callback)
    turbo.ioloop.instance():add_callback(function()
        local result = execute_command(command)
        callback(result)
    end)
end


-- Coroutine function to execute a long-running shell command asynchronously
local function execute_long_running_command(command, callback)
    turbo.ioloop.instance():add_callback(function()
    	local thread = turbo.thread.Thread(function(th)
        	turbo.log.notice("Executing command: " .. command)
        	local process = io.popen(command)
        	local output = ""
        	while creamRuns do
            	local chunk = process:read("*a")
            	if not chunk or chunk == "" then
                	break
            	end
            	output = output .. chunk
            	coroutine.yield()
        	end
        	--callback(output)
        	process:close()
        	turbo.log.notice("Command execution stopped.")
        	th:stop()
    	end)

    print(thread:wait_for_data())
    thread:wait_for_finish()
    turbo.ioloop.instance():close()

    end)
end

function creamWebStopHandler:get()
	local command = "killall arecord"
	creamRuns = false
   	execute_long_running_command(command, function(result)
   		self:write(result)
   		self:finish()
	end)
	CREAM.data.current_recording = ""
	self:write("Stopped Recording...<script>location.href = '/status';</script>")
end
 
function creamWebStartHandler:get()

	if creamRuns == true then 
		self:write("Recording already in progress " .. CREAM.data.current_recording .. " ... ")
	else

  	CREAM.data.current_recording = os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)") .. ".wav"
   	local command = "arecord -vvv -f cd -t wav " .. CREAM_ARCHIVE_DIRECTORY .. "/" 
													.. CREAM.data.current_recording .. " -d 0 2>&1 "

	creamRuns = true

   	execute_long_running_command(command, function(result)
   	end)

	self:write("Started Recording " .. CREAM.data.current_recording .. 
			" ... <script>location.href = '/status';</script>")

	end
end
 
function creamWebRecordStartHandler:get()
	self:finish()
end
 
function creamWebRecordStopHandler:get()
	self:finish()
end
-- cream Web Server

local creamWebApp = turbo.web.Application:new({
{"^/$", turbo.web.StaticFileHandler, "./html/index.html"},
{"^/(.*js)$", turbo.web.StaticFileHandler, "./html/"},
{"/(.*wav)$", turbo.web.StaticFileHandler, CREAM_ARCHIVE_DIRECTORY },
{"/status", creamWebStatusHandler},
{"/stop", creamWebStopHandler},
{"/start", creamWebStartHandler},
{"/recordStart", creamWebRecordStartHandler},
{"/recordStop", creamWebRecordStopHandler},
})

CREAM:init()

creamWebApp:listen(CREAM_APP_SERVER_PORT)

creamCOMMAND = nil

function creamMain()

	local commandWaiting = true
	while (cSTACK:size() ~= 0) do
		creamCOMMAND = cSTACK:pop()

		if (creamCOMMAND ~= nil) then
			creamCOMMAND() 
		end

		if (creamRuns) then
   		 	-- update
   		 	if (CREAM:update()) then
   		     -- execute
   		 	end
		end

	end

	turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + CREAM_COMMAND_INTERVAL, creamMain)

end

turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + CREAM_COMMAND_INTERVAL, creamMain)

turbo.ioloop.instance():start()

