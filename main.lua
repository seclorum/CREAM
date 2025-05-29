-- Import required modules
local config = require("config")
local turbo = require("turbo")
local turbo_thread = require("turbo.thread")
local io = require("io")
local posix = require("posix")
local syslog = require("posix.syslog")
local cjson = require("cjson")
local syscall = require("syscall")
local mustache = require("lua-mustache") -- Added Mustache dependency for templating

-- Global state flags
local creamIsExecuting = false
local creamIsPlaying = false
local creamIsSynchronizing = false

-- Set sync partner based on hostname (refactored for clarity)
local function setSyncPartner()
    local hostname = syscall.gethostname()
    if hostname == "mix-o" then
        config.CREAM_SYNC_PARTNER = "mix-j"
    elseif hostname == "mix-j" then
        config.CREAM_SYNC_PARTNER = "mix-o"
    else
        error("Unknown hostname: " .. hostname)
    end
end
setSyncPartner()

-- Disable buffering for stdout
io.stdout:setvbuf("no")

-- Load CREAM module
local CREAM = require("cream")

-- Initialize command stack
local cSTACK = turbo.structs.deque:new()

-- Logging utility function
local function cLOG(level, ...)
    local message = table.concat({...}, " ")
    syslog.syslog(level, message)
    print(string.format("LOG:%d %s", level, message))
end

-- Initialize application
cSTACK:append(function()
    local hostname = syscall.gethostname()
    config.dump()
    syslog.setlogmask(syslog.LOG_DEBUG)
    syslog.openlog(config.APP_NAME, syslog.LOG_SYSLOG)
    cLOG(syslog.LOG_INFO, string.format("%s running on host: %s protocol version %s on %s:%d",
        config.APP_NAME, hostname, config.CREAM_PROTOCOL_VERSION,
        config.CREAM_APP_SERVER_HOST, config.CREAM_APP_SERVER_PORT))
    cLOG(syslog.LOG_INFO, config.CREAM_APP_VERSION)

    CREAM.devices:init()
    CREAM.devices:dump()
end)

-- Mustache template for the status page
local statusTemplate = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CREAM::{{hostname}}</title>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js"></script>
    <style>
        body {
            font-family: 'Courier New', monospace;
            background-color: {{backgroundColor}};
            color: white;
        }
        h1, h2, h3, h4, h5, h6 { color: #999999; }
        a:link, a:visited { color: black; }
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
    <div class="collapsible" onclick="toggleContent()">::debug::
        <div id="json-container"></div>
    </div>

    <script>
        // Toggle debug JSON visibility
        function toggleContent() {
            var content = document.getElementById("json-container");
            content.style.display = content.style.display === "none" ? "block" : "none";
        }

        // Generate background color based on hostname
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

        // JSON object from server
        var jsonObject = {{{jsonData}}};

        // Prettify and render JSON for debug
        function prettifyAndRenderJSON(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var jsonString = JSON.stringify(jsonObj, null, 2)
                .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
            var prettyJson = jsonString.replace(
                /("(\\u[a-f0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g,
                function (match) {
                    var cls = /^"/.test(match) ? (/:$/.test(match) ? 'key' : 'string') :
                              /true|false/.test(match) ? 'boolean' :
                              /null/.test(match) ? 'null' : 'number';
                    return '<span class="' + cls + '">' + match + '</span>';
                }
            );
            prettyJson = prettyJson.replace(/"Tracks": \[\s*((?:"[^"]*",?\s*)+)\]/g, function (match, p1) {
                var links = p1.replace(/"([^"]*)"/g, '<span class="link" onclick="openLink(\'$1\')">$1</span>');
                return '"Tracks": [' + links + ']';
            });
            var preElement = document.createElement("pre");
            preElement.innerHTML = prettyJson;
            container.appendChild(preElement);
        }

        // Render WAV tracks with WaveSurfer
        function renderWAVTracks(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var tracks = jsonObj.app.edit.Tracks.sort();
            var wavTable = document.createElement("table");
            wavTable.border = "0";
            var waveformData = [];

            tracks.forEach(function(track, i) {
                var row = wavTable.insertRow(0);
                var cell = row.insertCell(0);
                var isCurrentRecording = jsonObj.app.edit.current_recording === track;
                var highlightStyle = isCurrentRecording ? 'style="background-color: red;"' : '';
                var linkClass = isCurrentRecording ? 'disabled' : 'link';
                var waveformId = 'waveform-' + i;

                cell.innerHTML = `<li ${highlightStyle}>
                    <a class="${linkClass}" href="/play/${track}">${track}</a>
                    <div id="${waveformId}" class="waveform-container"></div>
                    <div class="waveform-controls">
                        <button class="waveform-button" onclick="wavesurfers[${i}].playPause()">Play/Pause</button>
                        <button class="waveform-button" onclick="wavesurfers[${i}].skip(-5)">-5s</button>
                        <button class="waveform-button" onclick="wavesurfers[${i}].skip(5)">+5s</button>
                    </div></li>`;

                waveformData.push({ index: i, waveformId: waveformId, track: track });
            });

            container.appendChild(wavTable);

            window.wavesurfers = window.wavesurfers || [];
            waveformData.forEach(function(data) {
                try {
                    var wavesurfer = WaveSurfer.create({
                        container: '#' + data.waveformId,
                        waveColor: 'violet',
                        progressColor: 'purple',
                        height: 100,
                        responsive: true,
                        backend: 'MediaElement'
                    });
                    wavesurfer.load('/static/' + data.track);
                    wavesurfer.on('error', function(e) {
                        console.error('WaveSurfer error for ' + data.track + ':', e);
                    });
                    window.wavesurfers[data.index] = wavesurfer;
                } catch (e) {
                    console.error('Failed to initialize WaveSurfer for ' + data.track + ':', e);
                }
            });
        }

        // Render control interface
        function renderControlInterface(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var controlTable = document.createElement("table");
            controlTable.border = "0";
            var headerRow = controlTable.insertRow(0);
            var headerCell = headerRow.insertCell(0);

            headerCell.innerHTML = `
                <div class="control-surface">
                    ${jsonObj.app.edit.current_recording ?
                        '<div class="interface-button stop"><a href="/stop">STOP CAPTURE</a></div>' :
                        '<div class="interface-button start"><a href="/start">CAPTURE</a></div>'}
                    ${jsonObj.app.synchronizing ?
                        `<div class="interface-button synchronizing"><a href="/synchronize">SYNCHING ${jsonObj.partner} BIN</a></div>` :
                        `<div class="interface-button synchronize"><a href="/synchronize">SYNCH ${jsonObj.partner} BIN</a></div>`}
                    <div class="interface-button empty"><a href="/empty">CLEAR BIN</a></div>
                </div>`;
            container.appendChild(controlTable);
        }

        // Render status
        function renderStatus(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var statusTable = document.createElement("table");
            statusTable.border = "0";
            var headerRow = statusTable.insertRow(0);
            var headerCell = headerRow.insertCell(0);

            document.title = 'CREAM::' + jsonObj.hostname;
            headerCell.innerHTML = jsonObj.app.edit.current_recording ?
                `<h1>BIN:${jsonObj.hostname}</h1> <b>:: CAPTURE:</b><pre>${jsonObj.app.edit.current_recording}</pre>` :
                `<h1>BIN:${jsonObj.hostname}</h1> <b>:: </b>Not Currently Recording.`;
            container.appendChild(statusTable);
        }

        // Handle link clicks
        function openLink(fileName) {
            alert("Opening link: " + fileName);
        }

        // Apply hostname-specific background color
        if (jsonObject.hostname === "mix-o") {
            document.body.style.backgroundColor = "#8B4000";
        } else if (jsonObject.hostname === "mix-j") {
            document.body.style.backgroundColor = "#083F71";
        }

        // Render all components
        renderStatus(jsonObject, "current-status");
        renderControlInterface(jsonObject, "control-interface");
        prettifyAndRenderJSON(jsonObject, "json-container");
        renderWAVTracks(jsonObject, "wav-tracks");
    </script>
</body>
</html>
]]

-- Utility function to execute shell commands
local function executeCommand(command, callback, flag, resetFlag)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo.thread.Thread(function(th)
            cLOG(syslog.LOG_INFO, "Executing command: " .. command)
            local process = io.popen(command)
            local output = ""
            while flag() do
                local chunk = process:read("*a")
                if not chunk or chunk == "" then
                    break
                end
                output = output .. chunk
                coroutine.yield()
            end
            process:close()
            cLOG(syslog.LOG_INFO, "Command execution stopped: " .. command)
            if resetFlag then
                resetFlag(false)
            end
            th:stop()
        end)
        thread:wait_for_finish()
        if callback then
            callback(output)
        end
    end)
end

-- Web Handlers
local creamWebStatusHandler = class("creamWebStatusHandler", turbo.web.RequestHandler)
function creamWebStatusHandler:get()
    local hostname = syscall.gethostname()
    local userData = {
        hostname = hostname,
        partner = config.CREAM_SYNC_PARTNER,
        backgroundColor = hostname == "mix-o" and "#8B4000" or "#083F71",
        app = {
            recording = creamIsExecuting,
            synchronizing = creamIsSynchronizing,
            name = config.APP_NAME,
            version = config.CREAM_APP_VERSION,
            edit = CREAM.edit,
            io = { CREAM.devices.online }
        }
    }
    CREAM:update()
    local jsonData = cjson.encode(userData)
    local rendered = mustache.render(statusTemplate, {
        hostname = userData.hostname,
        backgroundColor = userData.backgroundColor,
        jsonData = jsonData
    })
    self:write(rendered)
    self:finish()
end
function creamWebStatusHandler:on_finish()
    collectgarbage("collect")
end

local creamWebStartHandler = class("creamWebStartHandler", turbo.web.RequestHandler)
function creamWebStartHandler:get()
    if creamIsExecuting then
        self:write("Recording already in progress: " .. CREAM.edit.current_recording)
        return
    end
    CREAM.edit.current_recording = string.format("%s::%s.wav",
        syscall.gethostname(),
        os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)"))
    local command = string.format(
        "/usr/bin/arecord -vvv -f cd -t wav %s%s -D plughw:CARD=MiCreator,DEV=0 2>&1 > %sarecord.log",
        config.CREAM_ARCHIVE_DIRECTORY, CREAM.edit.current_recording, config.CREAM_ARCHIVE_DIRECTORY)
    creamIsExecuting = true
    executeCommand(command, nil, function() return creamIsExecuting end, function(val) creamIsExecuting = val end)
    self:write(string.format("Started Recording %s%s ... <script>location.href = '/status';</script>",
        config.CREAM_ARCHIVE_DIRECTORY, CREAM.edit.current_recording))
end

local creamWebStopHandler = class("creamWebStopHandler", turbo.web.RequestHandler)
function creamWebStopHandler:get()
    local command = "killall arecord"
    creamIsExecuting = false
    CREAM.edit.current_recording = ""
    executeCommand(command, function(result)
        self:write(result)
        self:finish()
    end, function() return creamIsExecuting end)
    self:write("Stopped Recording...<script>location.href = '/status';</script>")
end

local creamWebEmptyHandler = class("creamWebEmptyHandler", turbo.web.RequestHandler)
function creamWebEmptyHandler:get()
    local command = string.format("find %s -name '*.wav' -exec rm -rf {} \\;", config.CREAM_ARCHIVE_DIRECTORY)
    creamIsExecuting = false
    CREAM.edit.current_recording = ""
    executeCommand(command, function(result)
        self:write(result)
        self:finish()
    end, function() return false end)
    self:write("Emptied recordings ...<script>location.href = '/status';</script>")
end

local creamWebSynchronizeHandler = class("creamWebSynchronizeHandler", turbo.web.RequestHandler)
function creamWebSynchronizeHandler:get()
    local command = creamIsSynchronizing and "killall rsync" or string.format(
        "rsync -avz --include='%s' ibi@%s.local:%s %s 2>&1 > %srsync.log",
        config.CREAM_SYNC_PARTNER, config.CREAM_SYNC_PARTNER, config.CREAM_ARCHIVE_DIRECTORY,
        config.CREAM_ARCHIVE_DIRECTORY, config.CREAM_ARCHIVE_DIRECTORY)
    creamIsSynchronizing = not creamIsSynchronizing
    executeCommand(command, nil, function() return creamIsSynchronizing end, function(val) creamIsSynchronizing = val end)
    self:write(string.format("Started Synchronizing ... <script>location.href = '/status';</script>"))
end

local creamWebPlayHandler = class("creamWebPlayHandler", turbo.web.RequestHandler)
function creamWebPlayHandler:get(fileToPlay)
    local command = string.format("/usr/bin/aplay %s%s -d 0 2>&1",
        config.CREAM_ARCHIVE_DIRECTORY, fileToPlay)
    creamIsPlaying = true
    executeCommand(command, nil, function() return creamIsPlaying end, function(val) creamIsPlaying = val end)
    self:write(string.format("Started Playing %s ... <script>location.href = '/status';</script>", fileToPlay))
end

local creamWebRecordStartHandler = class("creamWebRecordStartHandler", turbo.web.RequestHandler)
function creamWebRecordStartHandler:get()
    self:finish()
end

local creamWebRecordStopHandler = class("creamWebRecordStopHandler", turbo.web.RequestHandler)
function creamWebRecordStopHandler:get()
    self:finish()
end

local creamWavHandler = class("creamWavHandler", turbo.web.RequestHandler)
function creamWavHandler:get(wavFile)
    local wavFilePath = config.CREAM_ARCHIVE_DIRECTORY .. wavFile
    cLOG(syslog.LOG_INFO, "Serving WAV file: " .. wavFilePath)
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

-- Define web application routes
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

-- Initialize CREAM and start server
CREAM:init()
creamWebApp:listen(config.CREAM_APP_SERVER_PORT)

-- Main loop for processing command stack
local function creamMain()
    while cSTACK:size() > 0 do
        local command = cSTACK:pop()
        if command then
            command()
        end
        if creamIsExecuting and CREAM:update() then
            -- Handle updates if needed
        end
    end
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
end

-- Start the main loop and server
turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
turbo.ioloop.instance():start()
