
config = require ("config")

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
	local hostName = syscall.gethostname()
	config.dump()
	syslog.setlogmask(LOG_DEBUG)
	syslog.openlog(config.APP_NAME, LOG_SYSLOG)
	cLOG(syslog.LOG_INFO, config.APP_NAME .. " running on host: " .. syscall.gethostname() .. " protocol version " .. config.CREAM_PROTOCOL_VERSION .. " on " .. config.CREAM_APP_SERVER_HOST .. ":" .. config.CREAM_APP_SERVER_PORT)
	cLOG(syslog.LOG_INFO, config.CREAM_APP_VERSION)

 	CREAM.devices:init()
	--CREAM.mixer:init()
	--CREAM.devices:sync()
	CREAM.devices:dump()
	--CREAM.mixer:run()
end)


-- cream Web Handlers
local creamWebStatusHandler = class("creamWebStatusHandler", turbo.web.RequestHandler)
local creamWebStopHandler = class("creamWebStopHandler", turbo.web.RequestHandler)
local creamWebPlayHandler = class("creamWebPlayHandler", turbo.web.RequestHandler)
local creamWebStartHandler = class("creamWebStartHandler", turbo.web.RequestHandler)
local creamWebRecordStartHandler = class("creamWebRecordStartHandler", turbo.web.RequestHandler)
local creamWebRecordStopHandler = class("creamWebRecordStopHandler", turbo.web.RequestHandler)
local creamWavHandler = class("creamWavHandler", turbo.web.RequestHandler)


local responseHTML_A = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>cream::</title>
    <style>
    body {
    	font-family: 'Courier New', monospace; /* Use a monospaced font */
    	background-color: #1b2a3f; /* Grey-blue background color */
    	color: #6A9Ddb; /* Blue text color */
    }

    h1, h2, h3, h4, h5, h6 {
    	color: #999999; /* Black heading colors */
    }

    a {
    	color: #black;
    }

    #json-container {
    	font-family: 'Courier New', Courier, monospace;
    	white-space: pre-wrap;
    	background-color: #f9f9f9;
    	display: none;
    	padding: 0 18px;
    	overflow: hidden;
    	border: 1px solid #ddd;
    }

    .collapsible {
    	cursor: pointer;
    	padding: 18px;
    	text-align: left;
    	border: 1px solid #ddd;
    	margin-bottom: 16px;
    }

    .string {
    	color: black;
    }
    .number {
    	color: orange;
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
    	color: #999999; /* Black color for links */
    	text-decoration: underline;
    	cursor: pointer;
    }
    .highlight {
    	background-color: orange;
    }

    .control-surface {
      display: flex;
    }

    .recording-button {
      padding: 10px 20px;
      margin: 10px;
      font-size: 18px;
      text-align: center;
      text-transform: uppercase;
      cursor: pointer;
      border: 2px solid #fff;
      border-radius: 5px;
      background-color: #444;
      color: #fff;
      transition: background-color 0.3s, border-color 0.3s, color 0.3s;
    }

    .recording-button:hover {
      background-color: #fff;
      color: #333;
    }

    .stop {
      background-color: #4CAF50; /* Green */
      border-color: #4CAF50;
    }

    .start {
      background-color: #f44336; /* Red */
      border-color: #f44336;
    }

    </style>
</head>
<body>

<div id="current-status"></div>

<div class="control-surface">
<div class="recording-button start"><a href="/start">START RECORDING</a></div>
<div class="recording-button stop"><a href="/stop">STOP RECORDING</a></div>
</div>

<div id="wav-tracks"></div>

<div class="collapsible" onClick="toggleContent()">::debug::
<div id="json-container"></div>
</div>


<script>
function toggleContent() {
	var content = document.getElementById("json-container");
	if (content.style.display === "none") {
		content.style.display = "block";
	} else {
		content.style.display = "none";
	}
}
  
function generateBackgroundColor(str) {
  let hashCode = 0;
  for (let i = 0; i < str.length; i++) {
    hashCode = str.charCodeAt(i) + ((hashCode << 5) - hashCode);
  }

  const r = (hashCode & 0xFF0000) >> 16;
  const g = (hashCode & 0x00FF00) >> 8;
  const b = hashCode & 0x0000FF;

  return `rgb(${r},${g},${b})`;
}

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

	 // Convert clickable links in app.edit.Tracks array
    prettyJson = prettyJson.replace(/"Tracks": \[\s*((?:"[^"]*",?\s*)+)\]/g, function (match, p1) {
        var links = p1.replace(/"([^"]*)"/g, '<span class="link" onclick="openLink(\'$1\')">$1</span>');
        return '"Tracks": [' + links + ']';
    });

    // Wrap the pretty JSON in a <pre> element
    var preElement = document.createElement("pre");
    preElement.innerHTML = prettyJson;

    // Append the <pre> element to the container
    container.appendChild(preElement);

}

function renderWAVTracks(jsonObj, containerId) {
    var container = document.getElementById(containerId);
    var jsonString = JSON.stringify(jsonObj, null, 2);
		var Tracks = jsonObj.app.edit.Tracks;
		var sortedTracks = Tracks.sort();

        var wavTable = document.createElement("table");
        wavTable.border = "0";

        // Create wavTable header
        var headerRow = wavTable.insertRow(0);

        // Create wavTable rows with links
        for (var i = 0; i < sortedTracks.length; i++) {
		   highlight_style = "";
            var row = wavTable.insertRow(0);
            var cell = row.insertCell(0);
			if (jsonObj.app.edit.current_recording == sortedTracks[i]) {
	            highlight_style = 'style="background-color: red;"'
			}
            cell.innerHTML = '<li ' + highlight_style + '>' + 
								'<a class="link" href="/play/' + sortedTracks[i] + 
								'" target="_blank">' + sortedTracks[i] + '</a><pre>' +
								'<audio controls="controls"><source src="/static/' +
								sortedTracks[i] + 
								'" type="audio/x-wav" /></audio>' + 
								'</li>';
        }

        // Append the wavTable to the container
        container.appendChild(wavTable);
}

function renderStatus(jsonObj, containerId) {
    var currentRecording = jsonObj.app.edit.current_recording;
    var container = document.getElementById(containerId);
    var statusTable = document.createElement("table");
    statusTable.border = "0";

    document.title = 'CREAM::' + jsonObj.hostname;

    // Create wavTable header
    var headerRow = statusTable.insertRow(0);
    var headerCell = headerRow.insertCell(0);
	
	if (currentRecording) {
    		headerCell.innerHTML = '<h1>' + jsonObj.hostname + '</h1> <b>:: RECORDING:</b><pre>' + currentRecording + '</pre>'; 
	} else {
    		headerCell.innerHTML = '<h1>' + jsonObj.hostname + '</h1> <b>:: </b>Not Currently Recording.'; 
	}                                 

	container.appendChild(statusTable);
 
}


// Function to open the link (you can customize this based on your server)
function openLink(fileName) {
    alert("Opening link: " + fileName);
    // Replace the alert with logic to open the link on your server
}


// document.body.style.backgroundColor = generateBackgroundColor(jsonObject.hostname);
renderStatus(jsonObject, "current-status");
prettifyAndRenderJSON(jsonObject, "json-container");
renderWAVTracks(jsonObject, "wav-tracks");

//function renderJSON(jsonObj, containerId) {
//    var container = document.getElementById(containerId);
//    var jsonString = JSON.stringify(jsonObj, null, 8); // The third parameter (2) is for indentation
//    var preElement = document.createElement("pre");
//    preElement.textContent = jsonString;
//    container.appendChild(preElement);
//}
//renderJSON(jsonObject, "json-container");
</script>



</body>
</html>
]]


function creamWebStatusHandler:get()
	local hostName = syscall.gethostname()
	CREAM:update()
	local currentState = responseHTML_A .. 
				cjson.encode({ hostname = hostName, app = {recording = creamRuns, name = APP_NAME, version = config.CREAM_APP_VERSION, edit = CREAM.edit, io = { CREAM.devices.online } } }) .. 
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

function creamWebPlayHandler:get()
   	local command = "arecord -vvv -f cd -t wav " .. config.CREAM_ARCHIVE_DIRECTORY .. "/" 
													.. CREAM.edit.current_recording .. " -d 0 2>&1 "

	creamRuns = true

   	execute_long_running_command(command, function(result)
   	end)

	self:write("Started Recording " .. CREAM.edit.current_recording .. 
			" ... <script>location.href = '/status';</script>")
end

function creamWebStopHandler:get()
	local command = "killall arecord"
	creamRuns = false
   	execute_long_running_command(command, function(result)
   		self:write(result)
   		self:finish()
	end)
	CREAM.edit.current_recording = ""
	self:write("Stopped Recording...<script>location.href = '/status';</script>")
end
 
function creamWebStartHandler:get()

	if creamRuns == true then 
		self:write("Recording already in progress " .. CREAM.edit.current_recording .. " ... ")
	else

  	CREAM.edit.current_recording = os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)") .. ".wav"
   	local command = "arecord -vvv -f cd -t wav " .. config.CREAM_ARCHIVE_DIRECTORY .. "/" 
													.. CREAM.edit.current_recording .. " -d 0 2>&1 "

	creamRuns = true

   	execute_long_running_command(command, function(result)
   	end)

	self:write("Started Recording " .. CREAM.edit.current_recording .. 
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

function creamWavHandler:get(wavFile)


	local wavFilePath = config.CREAM_ARCHIVE_DIRECTORY .. wavFile

	cLOG(syslog.LOG_INFO, "wavFilePath " .. wavFilePath)
    local file = io.open(wavFilePath, "rb")


    if file then
        local content = file:read("*a")
        file:close()

        self:set_header("Content-Type", "audio/wav")
        self:write(content)
    else
        self:set_status(404)
        self:write("File not found")
    end

    self:finish()
end


local creamWebApp = turbo.web.Application:new({
{"/status", creamWebStatusHandler},
{"/start", creamWebStartHandler},
{"/stop", creamWebStopHandler},
{"/play", creamWebPlayHandler},
{"/recordStart", creamWebRecordStartHandler},
{"/recordStop", creamWebRecordStopHandler},
{"^/$", turbo.web.StaticFileHandler, "./html/index.html"},
--{"^/static/(.*)$", turbo.web.StaticFileHandler, config.CREAM_ARCHIVE_DIRECTORY },
{"^/static/(.*)$", creamWavHandler},
})

CREAM:init()

creamWebApp:listen(config.CREAM_APP_SERVER_PORT)

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

	turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)

end

turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)

turbo.ioloop.instance():start()

