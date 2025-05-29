config = require("config")

local turbo = require "turbo"
local turbo_thread = require "turbo.thread" 
local io = require "io" 
local posix = require "posix"
local syslog = require "posix.syslog"
local signal = require "posix.signal"
local cjson = require "cjson"
local syscall = require "syscall"

creamIsExecuting = false
creamIsPlaying = false
creamIsSynchronizing = false

-- !J! for the demo
if (syscall.gethostname() == "mix-o") then
    config.CREAM_SYNC_PARTNER = "mix-j"
end
if (syscall.gethostname() == "mix-j") then
    config.CREAM_SYNC_PARTNER = "mix-o"
end

io.stdout:setvbuf("no")

CREAM = require("cream")

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
    syslog.setlogmask(syslog.LOG_DEBUG)
    syslog.openlog(config.APP_NAME, syslog.LOG_SYSLOG)
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
local creamWebEmptyHandler = class("creamWebEmptyHandler", turbo.web.RequestHandler)
local creamWebPlayHandler = class("creamWebPlayHandler", turbo.web.RequestHandler)
local creamWebSynchronizeHandler = class("creamWebSynchronizeHandler", turbo.web.RequestHandler)
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
    <!-- Include WaveSurfer.js -->
    <script src="https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js"></script>
    <style>
    body {
        font-family: 'Courier New', monospace;
        background-color: #1b2a3f;
        color: white;
    }

    h1, h2, h3, h4, h5, h6 {
        color: #999999;
    }

    a:link, a:visited {
        color: black;
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

    .string { color: black; }
    .number { color: orange; }
    .key { color: blue; font-weight: bold; }
    .boolean { color: brown; }
    .null { color: white; }
    .link { color: #999999; text-decoration: underline; cursor: pointer; }
    .highlight { background-color: orange; }

    .control-surface { display: flex; }

    .interface-button { 
        width: 400px;
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

    .interface-button:hover {
        background-color: #fff;
        color: #333;
    }

    .start { background-color: #A7F9AB; border-color: #4CAF50; }
    .stop { background-color: #FBB1AB; border-color: #f44336; }
    .empty { background-color: #F9D4B4; border-color: white; }
    .synchronize { background-color: #CBB1FE; border-color: green; }
    .synchronizing { background-color: green; border-color: #CBB1FE; }

    /* Waveform styling */
    .waveform-container {
        width: 100%;
        height: 100px;
        margin: 10px 0;
        background-color: #222;
        border: 1px solid #444;
    }
    .waveform-controls {
        margin-top: 5px;
    }
    .waveform-button {
        padding: 5px 10px;
        margin-right: 5px;
        background-color: #555;
        color: white;
        border: none;
        border-radius: 3px;
        cursor: pointer;
    }
    .waveform-button:hover {
        background-color: #777;
    }
    </style>
</head>
<body>

<div id="current-status"></div>

<div id="control-interface"></div>

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

function prettifyAndRenderJSON(jsonObj, containerId) {
    var container = document.getElementById(containerId);
    var jsonString = JSON.stringify(jsonObj, null, 2);
    jsonString = jsonString.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    var prettyJson = jsonString.replace(/("(\\u[a-f0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g,
        function (match) {
            var cls = 'number';
            if (/^"/.test(match)) {
                if (/:$/.test(match)) {
                    cls = 'key';
                } else {
                    cls = 'string';
                }
            } else if (/true|false/.test(match)) {
                cls = 'boolean';
            } else if (/null/.test(match)) {
                cls = 'null';
            }
            return '<span class="' + cls + '">' + match + '</span>';
        });
    prettyJson = prettyJson.replace(/"Tracks": \[\s*((?:"[^"]*",?\s*)+)\]/g, function (match, p1) {
        var links = p1.replace(/"([^"]*)"/g, '<span class="link" onclick="openLink(\'$1\')">$1</span>');
        return '"Tracks": [' + links + ']';
    });
    var preElement = document.createElement("pre");
    preElement.innerHTML = prettyJson;
    container.appendChild(preElement);
}

function renderWAVTracks(jsonObj, containerId) {
    var container = document.getElementById(containerId);
    var jsonString = JSON.stringify(jsonObj, null, 2);
    var Tracks = jsonObj.app.edit.Tracks;
    var sortedTracks = Tracks.sort();
    var wavTable = document.createElement("table");
    wavTable.border = "0";

    for (var i = 0; i < sortedTracks.length; i++) {
        var highlight_style = "";
        var link_class = "disabled";
        var row = wavTable.insertRow(0);
        var cell = row.insertCell(0);

        if (jsonObj.app.edit.current_recording == sortedTracks[i]) {
            highlight_style = 'style="background-color: red;"';
        } else {
            link_class = "link";
        }

        // Create a unique waveform container ID
        var waveformId = 'waveform-' + i;
        cell.innerHTML = '<li ' + highlight_style + '>' +
            '<a class="' + link_class + '" href="/play/' + sortedTracks[i] + '">' + sortedTracks[i] + '</a>' +
            '<div id="' + waveformId + '" class="waveform-container"></div>' +
            '<div class="waveform-controls">' +
            '<button class="waveform-button" onclick="wavesurfers[' + i + '].playPause()">Play/Pause</button>' +
            '<button class="waveform-button" onclick="wavesurfers[' + i + '].skip(-5)">-5s</button>' +
            '<button class="waveform-button" onclick="wavesurfers[' + i + '].skip(5)">+5s</button>' +
            '</div></li>';

        // Initialize WaveSurfer for this track
        (function(index, waveformId, track) {
            var wavesurfer = WaveSurfer.create({
                container: '#' + waveformId,
                waveColor: 'violet',
                progressColor: 'purple',
                height: 100,
                responsive: true,
                backend: 'MediaElement' // Fallback for compatibility on Raspberry Pi browsers
            });
            wavesurfer.load('/static/' + track);
            window.wavesurfers = window.wavesurfers || [];
            window.wavesurfers[index] = wavesurfer;
        })(i, waveformId, sortedTracks[i]);
    }

    container.appendChild(wavTable);
}

function renderControlInterface(jsonObj, containerId) {
    var currentRecording = jsonObj.app.edit.current_recording;
    var currentSynchronizing = jsonObj.app.synchronizing;
    var container = document.getElementById(containerId);
    var controlTable = document.createElement("table");
    controlTable.border = "0";
    var headerRow = controlTable.insertRow(0);
    var headerCell = headerRow.insertCell(0);

    headerCell.innerHTML = '<div class="control-surface">';
    if (currentRecording) {
        headerCell.innerHTML += '<div class="interface-button stop"><a href="/stop">STOP CAPTURE</a></div>';
    } else {
        headerCell.innerHTML += '<div class="interface-button start"><a href="/start">CAPTURE</a></div>';
    }
    if (currentSynchronizing) {
        headerCell.innerHTML += '<div class="interface-button synchronizing"><a href="/synchronize">SYNCHING ' + jsonObj.partner + ' BIN</a></div>';
    } else {
        headerCell.innerHTML += '<div class="interface-button synchronize"><a href="/synchronize">SYNCH ' + jsonObj.partner + ' BIN</a></div>';
    }
    headerCell.innerHTML += '<div class="interface-button empty"><a href="/empty">CLEAR BIN</a></div>';
    headerCell.innerHTML += '</div>';

    container.appendChild(controlTable);
}

function renderStatus(jsonObj, containerId) {
    var currentRecording = jsonObj.app.edit.current_recording;
    var container = document.getElementById(containerId);
    var statusTable = document.createElement("table");
    statusTable.border = "0";

    document.title = 'CREAM::' + jsonObj.hostname;

    var headerRow = statusTable.insertRow(0);
    var headerCell = headerRow.insertCell(0);

    if (currentRecording) {
        headerCell.innerHTML = '<h1>BIN:' + jsonObj.hostname + '</h1> <b>:: CAPTURE:</b><pre>' + currentRecording + '</pre>';
    } else {
        headerCell.innerHTML = '<h1>BIN:' + jsonObj.hostname + '</h1> <b>:: </b>Not Currently Recording.';
    }

    container.appendChild(statusTable);
}

function openLink(fileName) {
    alert("Opening link: " + fileName);
}

if (jsonObject.hostname == "mix-o") {
    document.body.style.backgroundColor = "#8B4000";
}
if (jsonObject.hostname == "mix-j") {
    document.body.style.backgroundColor = "#083F71";
}

renderStatus(jsonObject, "current-status");
renderControlInterface(jsonObject, "control-interface");
prettifyAndRenderJSON(jsonObject, "json-container");
renderWAVTracks(jsonObject, "wav-tracks");
</script>
</body>
</html>
]]

-- !J! TODO: finish Mustache implementation
function creamWebStatusHandler:get()
    local hostName = syscall.gethostname()
    local userData = { 
        hostname = hostName, 
        partner = config.CREAM_SYNC_PARTNER, 
        app = {
            recording = creamIsExecuting, 
            synchronizing = creamIsSynchronizing, 
            name = config.APP_NAME, 
            version = config.CREAM_APP_VERSION, 
            edit = CREAM.edit, 
            io = { CREAM.devices.online } 
        } 
    }
    local asJson = cjson.encode(userData)
    local responseData = { userData = userData, asJson = asJson }
    local webStatusResponse = responseHTML_A .. cjson.encode(userData) .. responseHTML_B

    CREAM:update()
    self:write(webStatusResponse)
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
            if (creamIsExecuting) then
                turbo.log.notice("creamIsExecuting!")
            else
                turbo.log.notice("creamIsNOTExecuting?")
            end
            local process = io.popen(command)
            local output = ""
            while creamIsExecuting do
                local chunk = process:read("*a")
                if not chunk or chunk == "" then
                    break
                end
                output = output .. chunk
                coroutine.yield()
            end
            process:close()
            turbo.log.notice("Command execution stopped.")
            th:stop()
        end)
        print(thread:wait_for_data())
        thread:wait_for_finish()
        turbo.ioloop.instance():close()
    end)
end

-- like long_running_command, but for rsync = !J! HACK 
local function execute_long_running_rsync(command, callback)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo.thread.Thread(function(th)
            turbo.log.notice("Executing command: " .. command)
            if (creamIsSynchronizing) then
                turbo.log.notice("creamIsSynchronizing!")
            else
                turbo.log.notice("creamIsNOTSynching?")
            end
            local process = io.popen(command)
            local output = ""
            while creamIsSynchronizing do
                local chunk = process:read("*a")
                if not chunk or chunk == "" then
                    break
                end
                output = output .. chunk
                coroutine.yield()
            end
            creamIsSynchronizing = false
            process:close()
            turbo.log.notice("Command execution stopped.")
            th:stop()
        end)
        print(thread:wait_for_data())
        thread:wait_for_finish()
        turbo.ioloop.instance():close()
    end)
end

-- like long_running_command, but for playing = !J! HACK 
local function execute_long_running_play(command, callback)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo.thread.Thread(function(th)
            turbo.log.notice("Executing command: " .. command)
            local process = io.popen(command)
            local output = ""
            while creamIsPlaying do
                local chunk = process:read("*a")
                if not chunk or chunk == "" then
                    break
                end
                output = output .. chunk
                coroutine.yield()
            end
            process:close()
            turbo.log.notice("Command execution stopped.")
            th:stop()
        end)
        print(thread:wait_for_data())
        thread:wait_for_finish()
        turbo.ioloop.instance():close()
    end)
end

function creamWebPlayHandler:get(fileToPlay)
    local command = "/usr/bin/aplay " .. config.CREAM_ARCHIVE_DIRECTORY .. fileToPlay .. " -d 0 2>&1 "
    creamIsPlaying = true
    execute_long_running_play(command, function(result)
        creamIsPlaying = false
    end)
    self:write("Started Playing " .. fileToPlay .. " ... <script>location.href = '/status';</script>")
end

function creamWebSynchronizeHandler:get()
    local command = ""
    if (creamIsSynchronizing) then
        command = "killall rsync"
        creamIsSynchronizing = false
    else
        command = "rsync -avz --include='" .. config.CREAM_SYNC_PARTNER .. 
                "' ibi@" .. config.CREAM_SYNC_PARTNER .. 
                ".local:" .. config.CREAM_ARCHIVE_DIRECTORY .. 
                " " .. config.CREAM_ARCHIVE_DIRECTORY .. " 2>&1 > " .. config.CREAM_ARCHIVE_DIRECTORY ..  "rsync.log"
        creamIsSynchronizing = true
    end
    execute_long_running_rsync(command, function(result) end)
    self:write("Started Synchronizing " .. " ... <script>location.href = '/status';</script>")
end

function creamWebStopHandler:get()
    local command = "killall arecord"
    creamIsExecuting = false
    execute_long_running_command(command, function(result)
        self:write(result)
        self:finish()
    end)
    CREAM.edit.current_recording = ""
    self:write("Stopped Recording...<script>location.href = '/status';</script>")
end

function creamWebEmptyHandler:get()
    local command = "find " .. config.CREAM_ARCHIVE_DIRECTORY .. " -name *.wav -exec rm -rf {} \\;"
    creamIsExecuting = false
    execute_long_running_command(command, function(result)
        self:write(result)
        self:finish()
    end)
    CREAM.edit.current_recording = ""
    self:write("Emptied recordings ...<script>location.href = '/status';</script>")
end

function creamWebStartHandler:get()
    if creamIsExecuting == true then 
        self:write("Recording already in progress " .. CREAM.edit.current_recording .. " ... ")
    else
        CREAM.edit.current_recording = syscall.gethostname() .. "::" .. os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)") .. ".wav"
        local command = "/usr/bin/arecord -vvv -f cd -t wav " .. config.CREAM_ARCHIVE_DIRECTORY .. CREAM.edit.current_recording .. " -D plughw:CARD=MiCreator,DEV=0 2>&1 > " .. config.CREAM_ARCHIVE_DIRECTORY ..  "arecord.log"
        creamIsExecuting = true
        execute_long_running_command(command, function(result) end)
        self:write("Started Recording " .. config.CREAM_ARCHIVE_DIRECTORY .. CREAM.edit.current_recording .. " ... <script>location.href = '/status';</script>")
    end
end

function creamWebRecordStartHandler:get()
    self:finish()
end

function creamWebRecordStopHandler:get()
    self:finish()
end

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
    {"/empty", creamWebEmptyHandler},
    {"/synchronize", creamWebSynchronizeHandler},
    {"/play/(.*)$", creamWebPlayHandler},
    {"/recordStart", creamWebRecordStartHandler},
    {"/recordStop", creamWebRecordStopHandler},
    {"^/$", turbo.web.StaticFileHandler, "./html/index.html"},
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
        if (creamIsExecuting) then
            if (CREAM:update()) then
                -- execute
            end
        end
    end
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
end

turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)

turbo.ioloop.instance():start()
