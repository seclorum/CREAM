#!/usr/bin/env luajit

-- Ensure luarocks local paths are included
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.luarocks/share/lua/5.1/?.lua;" .. os.getenv("HOME") .. "/.luarocks/share/lua/5.1/?/init.lua"
package.cpath = package.cpath .. ";" .. os.getenv("HOME") .. "/.luarocks/lib/lua/5.1/?.so"

-- Import required modules
local turbo = require("turbo") -- TurboLua web framework
local turbo_thread = require("turbo.thread") -- Threading support
local sqlite3 = require("lsqlite3") -- SQLite database support
local lfs = require("luafilesystem_ffi_scm_1-lfs") or require("luafilesystem")
local cjson = require("cjson") -- JSON encoding/decoding
local config = require("config") -- Configuration module
local posix = require("posix") -- POSIX system calls
local syslog = require("posix.syslog") -- System logging
local syscall = require("syscall") -- System call utilities
local socket = require("socket") -- For port availability checking
local CREAM = require("cream") -- Core CREAM module
local io = require("io") -- Standard I/O library

-- Configuration
local IPFS_GATEWAY = "https://"
 -- IPFS gateway URL
local DB_NAME = config.CREAM_ARCHIVE_DIRECTORY .. "ipfs_wavs.db" -- SQLite database path
local WAV_DIR = config.CREAM_ARCHIVE_DIRECTORY -- Directory for .wav files
local APP_NAME = config.APP_NAME -- Application name ("cream audio broker")
local APP_SERVER_HOST = config.CREAM_APP_SERVER_HOST -- Server host ("localhost")
local APP_SERVER_PORT = config.CREAM_APP_SERVER_PORT -- Server port (8081 or arg[1])
local COMMAND_INTERVAL = config.CREAM_COMMAND_INTERVAL -- Command loop interval (200 ms)
local ARCHIVE_DIRECTORY = WAV_DIR -- Directory for recordings
local APP_VERSION = config.CREAM_APP_VERSION or "{\"Version\":\"1.0\", \"buildDate\":\"unknown\"}" -- Fallback
local STATIC_DIRECTORY = config.CREAM_STATIC_DIRECTORY -- Static files directory

-- Global state variables
local creamIsExecuting = false -- Tracks if a recording is in progress
local creamIsPlaying = false -- Tracks if audio playback is active
local creamIsSynchronizing = false -- Tracks if synchronization is active

-- Logging utility function
local function cLOG(level, ...)
    local message = table.concat({...}, " ") -- Concatenate log message arguments
    syslog.syslog(level, message) -- Log to syslog
    print(string.format("LOG:%d %s", level, message)) -- Print to console
end

-- Set sync partner based on hostname
local function setSyncPartner()
    local hostname = syscall.gethostname() -- Get current hostname
    if hostname == "mix-o" then
        config.CREAM_SYNC_PARTNER = "mix-j" -- Set sync partner for mix-o
    elseif hostname == "mix-j" then
        config.CREAM_SYNC_PARTNER = "mix-o" -- Set sync partner for mix-j
    else
        config.CREAM_SYNC_PARTNER = nil -- No sync partner for unknown hosts
        cLOG(syslog.LOG_WARNING, "Unknown hostname, sync not supported: " .. hostname)
    end
end
setSyncPartner()

-- Disable buffering for stdout
io.stdout:setvbuf("no") -- Ensures immediate console output

-- Check if port is in use using Lua socket
local function isPortInUse(port)
    local sock, err = socket.bind("0.0.0.0", port) -- Attempt to bind to port
    if sock then
        sock:close() -- Close socket if bind succeeds
        return false -- Port is available
    end
    cLOG(syslog.LOG_DEBUG, "Port check error: " .. tostring(err))
    return true -- Port is in use
end

-- Setup SQLite database
local function setup_database()
    local db = sqlite3.open(DB_NAME)
    local query = [[
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            friendly_name TEXT NOT NULL,
            cid TEXT,
            url TEXT,
            encrypted INTEGER NOT NULL,
            password TEXT,
            status TEXT NOT NULL
        )
    ]]
    local status = db:exec(query)
    db:close()
    if status ~= sqlite3.OK then
        error("Error creating database: " .. db:errmsg())
    end
end

-- Execute shell command with threading
local function executeCommand(command, callback, flag, resetFlag)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo.thread.Thread(function(th)
            cLOG(syslog.LOG_INFO, "Executing command: " .. command)
            local process = io.popen(command .. " ; echo $?")
            local output = ""
            local exitCode
            while true do
                local chunk = process:read("*l")
                if not chunk then break end
                if chunk:match("^%d+$") then
                    exitCode = tonumber(chunk)
                else
                    output = output .. chunk .. "\n"
                end
                if flag and not flag() then break end
                coroutine.yield()
            end
            process:close()
            if exitCode and exitCode ~= 0 then
                cLOG(syslog.LOG_ERR, "Command failed with exit code " .. exitCode .. ": " .. command .. "\nOutput: " .. output)
            else
                cLOG(syslog.LOG_INFO, "Command execution stopped: " .. command .. "\nOutput: " .. output)
            end
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

-- Check and start IPFS daemon
local function ensure_ipfs_daemon()
    local check = io.popen("pgrep ipfs"):read("*a")
    if check == "" then
        executeCommand("ipfs daemon &", nil, function() return false end)
        turbo.util.sleep(5000) -- Wait for daemon to start
    end
    local response = io.popen("curl -s http://localhost:5001/api/v0/id"):read("*a")
    if response == "" then
        error("IPFS daemon not responding")
    end
end

-- Generate secure password (placeholder)
local function generate_password(length)
    return "placeholder_password_" .. os.time() -- Replace with secure random generation
end

-- Store file metadata in database
local function store_in_database(filename, friendly_name, cid, encrypted, password, status)
    local encoded_filename = filename:gsub("([^%w ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+")
    local url = cid and (IPFS_GATEWAY .. cid .. "?filename=" .. encoded_filename) or ""

    local db = sqlite3.open(DB_NAME)
    local stmt
    if encrypted and password then
        stmt = db:prepare([[
            INSERT INTO files (filename, friendly_name, cid, url, encrypted, password, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]])
        stmt:bind_values(filename, friendly_name, cid or "", url, 1, password, status)
    else
        stmt = db:prepare([[
            INSERT INTO files (filename, friendly_name, cid, url, encrypted, password, status)
            VALUES (?, ?, ?, ?, ?, NULL, ?)
        ]])
        stmt:bind_values(filename, friendly_name, cid or "", url, 0, status)
    end
    local status, err = pcall(function() stmt:step() end)
    stmt:finalize()
    db:close()
    if not status then
        return nil, "Error storing in database: " .. tostring(err)
    end
    return url
end

-- List files in database
local function list_files()
    local db = sqlite3.open(DB_NAME)
    local files = {}
    local stmt = db:prepare("SELECT id, filename, friendly_name, cid, url, encrypted, password, status FROM files")
    for row in stmt:nrows() do
        table.insert(files, {
            id = row.id,
            filename = row.filename,
            friendly_name = row.friendly_name,
            cid = row.cid,
            url = row.url,
            encrypted = row.encrypted == 1 and "Yes" or "No",
            password = row.encrypted == 1 and (row.password or "N/A") or "N/A",
            status = row.status
        })
    end
    stmt:finalize()
    db:close()
    return files
end

-- List .wav files in WAV_DIR
local function list_wav_files()
    local files = {}
    for file in lfs.dir(WAV_DIR) do
        if file:match("%.wav$") then
            table.insert(files, file)
        end
    end
    return files
end

-- Add file to IPFS
local function add_file_to_ipfs(file_path, do_pin)
    if not file_path:match("%.wav$") then
        return nil, "Error: File must be a .wav file."
    end
    if not io.open(file_path, "r") then
        return nil, "Error: File does not exist."
    end
    local cmd = string.format("ipfs add %q", file_path)
    local output = io.popen(cmd):read("*a")
    local cid = output:match("added (%S+)")
    if not cid then
        return nil, "Error: Failed to get CID from IPFS."
    end
    if do_pin then
        local pin_cmd = string.format("ipfs pin add %q", cid)
        executeCommand(pin_cmd, nil, function() return false end)
    end
    return cid
end

-- Initialize application
local cSTACK = turbo.structs.deque:new()
cSTACK:append(function()
    local hostname = syscall.gethostname()
    config.dump() -- Dump configuration
    syslog.setlogmask(syslog.LOG_DEBUG) -- Set syslog debug level
    syslog.openlog(config.APP_NAME, syslog.LOG_SYSLOG) -- Initialize syslog
    cLOG(syslog.LOG_INFO, string.format("%s running on host: %s protocol version %s on %s:%d",
        APP_NAME, hostname, config.CREAM_PROTOCOL_VERSION,
        APP_SERVER_HOST, APP_SERVER_PORT))
    cLOG(syslog.LOG_INFO, APP_VERSION)

    local status, err = pcall(function()
        CREAM.devices = CREAM.devices or { online = {}, init = function() end, dump = function() end }
        CREAM.devices:init()
        CREAM.devices:dump()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Failed to initialize CREAM devices: " .. tostring(err) .. "\nStack: " .. debug.traceback())
    end
end)

-- Mustache template
local template = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CREAM::{{hostname}}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js" onerror="console.error('Failed to load wavesurfer.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/regions.min.js" onerror="console.error('Failed to load regions.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/envelope.min.js" onerror="console.error('Failed to load envelope.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/hover.min.js" onerror="console.error('Failed to load hover.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/minimap.min.js" onerror="console.error('Failed to load minimap.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/spectrogram.min.js" onerror="console.error('Failed to load spectrogram.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/timeline.min.js" onerror="console.error('Failed to load timeline.min.js')"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/zoom.min.js" onerror="console.error('Failed to load zoom.min.js')"></script>
    <style>
        body {
            font-family: 'Courier New', monospace;
            background-color: {{backgroundColor}};
            color: white;
            margin: 20px;
        }
        h1, h2, h3 { color: #999999; }
        a:link, a:visited { color: black; }
        #json-container {
            font-family: 'Courier New', monospace;
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
        .link { color: blue; text-decoration: underline; cursor: pointer; }
        .highlight { background-color: orange; }
        .control-surface { display: flex; flex-wrap: wrap; }
        .interface-button {
            width: 150px;
            padding: 10px 20px;
            margin: 10px;
            font-size: 16px;
            text-align: center;
            text-transform: uppercase;
            cursor: pointer;
            border: 2px solid #fff;
            border-radius: 5px;
            background-color: #444;
            color: #fff;
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
            display: flex;
            flex-wrap: wrap;
            gap: 5px;
            align-items: center;
        }
        .waveform-button {
            padding: 5px 10px;
            background-color: #555;
            color: white;
            border: none;
            border-radius: 3px;
            cursor: pointer;
        }
        .waveform-button:hover { background-color: #777; }
        .waveform-button.active { background-color: #4CAF50; }
        .silence-params {
            display: flex;
            gap: 5px;
            align-items: center;
        }
        .silence-params input {
            width: 60px;
            padding: 2px;
            font-size: 12px;
        }
        .region-label {
            font-size: 12px;
            color: #ccc;
            margin-left: 10px;
        }
        .ws-region { background: rgba(0, 255, 0, 0.3); }
        .ws-minimap {
            margin-top: 5px;
            background-color: #333;
            border: 1px solid #444;
        }
        .ws-spectrogram { margin-top: 10px; }
        .ws-timeline { margin-top: 5px; }
        .ws-hover { background: rgba(255, 255, 255, 0.2); }
        .error-message { color: red; font-size: 12px; margin-left: 10px; }
        .table { color: white; }
        .alert { margin-top: 10px; }
    </style>
</head>
<body>
    <script>
        window.addEventListener('load', function() {
            console.log('Final plugins status:', {
                regions: !!WaveSurfer.regions,
                envelope: !!WaveSurfer.envelope,
                hover: !!WaveSurfer.hover,
                minimap: !!WaveSurfer.minimap,
                spectrogram: !!WaveSurfer.spectrogram,
                timeline: !!WaveSurfer.timeline,
                zoom: !!WaveSurfer.zoom
            });
        });

        function waitForPlugins(callback) {
            const plugins = ['regions', 'envelope', 'hover', 'minimap', 'spectrogram', 'timeline', 'zoom'];
            let loaded = 0;
            function checkPlugin() {
                if (typeof WaveSurfer !== 'undefined' && plugins.every(p => WaveSurfer[p])) {
                    console.log('All plugins loaded:', Object.keys(WaveSurfer));
                    callback();
                } else {
                    loaded++;
                    if (loaded < 100) {
                        setTimeout(checkPlugin, 100);
                    } else {
                        console.error('Plugin loading timeout:', {
                            regions: !!WaveSurfer.regions,
                            envelope: !!WaveSurfer.envelope,
                            hover: !!WaveSurfer.hover,
                            minimap: !!WaveSurfer.minimap,
                            spectrogram: !!WaveSurfer.spectrogram,
                            timeline: !!WaveSurfer.timeline,
                            zoom: !!WaveSurfer.zoom
                        });
                        document.getElementById('current-status').innerHTML += '<p class="error-message">Error: Some plugins failed to load.</p>';
                        callback();
                    }
                }
            }
            checkPlugin();
        }

        function toggleContent() {
            var content = document.getElementById("json-container");
            content.style.display = content.style.display === 'none' ? 'block' : 'none';
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

        var jsonObject = {{{jsonData}}};

        function prettifyAndRenderJSON(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var jsonString = JSON.stringify(jsonObj, null, 2)
                .replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
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

        function detectSilence(audioBuffer, sampleRate, threshold, minSilenceDuration) {
            const samples = audioBuffer.getChannelData(0);
            const minSamples = minSilenceDuration * sampleRate;
            const regions = [];
            let silenceStart = null;
            const thresholdAmplitude = Math.pow(10, threshold / 20);

            for (let i = 0; i < samples.length; i++) {
                const amplitude = Math.abs(samples[i]);
                if (amplitude < thresholdAmplitude) {
                    if (silenceStart === null) {
                        silenceStart = i;
                    }
                } else {
                    if (silenceStart !== null && (i - silenceStart) >= minSamples) {
                        regions.push({
                            start: silenceStart / sampleRate,
                            end: i / sampleRate
                        });
                    }
                    silenceStart = null;
                }
            }
            if (silenceStart !== null && (samples.length - silenceStart) >= minSamples) {
                regions.push({
                    start: silenceStart / sampleRate,
                    end: samples.length / sampleRate
                });
            }
            return regions;
        }

        function renderWAVTracks(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            container.innerHTML = '';
            var tracks = (jsonObj.app.edit.Tracks || []).sort();
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
                        <button class="waveform-button" onclick="wavesurfers[${i}]?.playPause()">Play/Pause</button>
                        <button class="waveform-button" onclick="wavesurfers[${i}]?.skip(-5)">-5s</button>
                        <button class="waveform-button" onclick="wavesurfers[${i}]?.skip(5)">+5s</button>
                        <button class="waveform-button silence-toggle" onclick="toggleSilenceDetection(${i})">Detect Silence</button>
                        <button class="waveform-button" onclick="clearRegions(${i})">Clear Regions</button>
                        <div class="silence-params">
                            <label>Threshold (dB):</label>
                            <input type="number" id="silence-threshold-${i}" value="-40" step="1">
                            <label>Min Duration (s):</label>
                            <input type="number" id="silence-duration-${i}" value="0.5" step="0.1">
                        </div>
                        <button class="waveform-button envelope-toggle" onclick="toggleEnvelope(${i})">Toggle Envelope</button>
                        <button class="waveform-button minimap-toggle" onclick="toggleMinimap(${i})">Toggle Minimap</button>
                        <button class="waveform-button spectrogram-toggle" onclick="toggleSpectrogram(${i})">Toggle Spectrogram</button>
                        <button class="waveform-button timeline-toggle" onclick="toggleTimeline(${i})">Toggle Timeline</button>
                        <button class="waveform-button" onclick="zoomIn(${i})">Zoom In</button>
                        <button class="waveform-button" onclick="zoomOut(${i})">Zoom Out</button>
                        <span class="region-label" id="region-label-${i}"></span>
                        <span class="error-message" id="error-${i}"></span>
                    </div></li>`;

                waveformData.push({ index: i, waveformId: waveformId, track: track });
            });

            container.appendChild(wavTable);

            window.wavesurfers = window.wavesurfers || [];
            waveformData.forEach(function(data) {
                try {
                    if (typeof WaveSurfer === 'undefined') {
                        throw new Error('WaveSurfer.js failed to load');
                    }

                    var wavesurfer = WaveSurfer.create({
                        container: '#' + data.waveformId,
                        waveColor: 'violet',
                        progressColor: 'purple',
                        height: 100,
                        responsive: true,
                        backend: 'MediaElement',
                        plugins: [
                            WaveSurfer.regions ? WaveSurfer.regions.create() : null,
                            WaveSurfer.envelope ? WaveSurfer.envelope.create({
                                volume: 1.0,
                                fadeInStart: 0,
                                fadeInEnd: 0,
                                fadeOutStart: 0,
                                fadeOutEnd: 0
                            }) : null,
                            WaveSurfer.hover ? WaveSurfer.hover.create({
                                lineColor: '#fff',
                                lineWidth: 2,
                                labelBackground: '#555',
                                labelColor: '#fff'
                            }) : null,
                            WaveSurfer.minimap ? WaveSurfer.minimap.create({
                                height: 30,
                                waveColor: '#ddd',
                                progressColor: '#999'
                            }) : null,
                            WaveSurfer.spectrogram ? WaveSurfer.spectrogram.create({
                                container: '#' + data.waveformId + '-spectrogram',
                                fftSamples: 512,
                                labels: true
                            }) : null,
                            WaveSurfer.timeline ? WaveSurfer.timeline.create({
                                container: '#' + data.waveformId + '-timeline'
                            }) : null,
                            WaveSurfer.zoom ? WaveSurfer.zoom.create({
                                zoom: 100
                            }) : null
                        ].filter(plugin => plugin !== null)
                    });

                    var waveformContainer = document.getElementById(data.waveformId);
                    var spectrogramDiv = document.createElement('div');
                    spectrogramDiv.id = data.waveformId + '-spectrogram';
                    spectrogramDiv.className = 'ws-spectrogram';
                    waveformContainer.parentNode.insertBefore(spectrogramDiv, waveformContainer.nextSibling);
                    var timelineDiv = document.createElement('div');
                    timelineDiv.id = data.waveformId + '-timeline';
                    timelineDiv.className = 'ws-timeline';
                    waveformContainer.parentNode.insertBefore(timelineDiv, spectrogramDiv.nextSibling);

                    wavesurfer.load('/static/' + data.track);

                    wavesurfer.on('ready', function() {
                        window.wavesurfers[data.index] = wavesurfer;
                        wavesurfer.isSilenceDetected = false;
                        wavesurfer.isMinimapVisible = true;
                        wavesurfer.isSpectrogramVisible = false;
                        wavesurfer.isTimelineVisible = false;
                        wavesurfer.isEnvelopeApplied = false;
                        if (wavesurfer.spectrogram) wavesurfer.spectrogram.hide();
                        if (wavesurfer.timeline) wavesurfer.timeline.hide();
                    });

                    if (wavesurfer.regions) {
                        wavesurfer.on('region-click', function(region) {
                            wavesurfer.play(region.start, region.end);
                        });
                        wavesurfer.on('region-created', function() {
                            updateRegionLabel(data.index, Object.keys(wavesurfer.regions.list).length);
                        });
                    }

                    wavesurfer.on('error', function(e) {
                        console.error('WaveSurfer error for ' + data.track + ':', e);
                        document.getElementById('error-' + data.index).textContent = 'Error: ' + e.message;
                    });

                    window.wavesurfers[data.index] = wavesurfer;
                } catch (e) {
                    console.error('Failed to initialize WaveSurfer for ' + data.track + ':', e);
                    document.getElementById('error-' + data.index).textContent = 'Failed to load waveform: ' + e.message;
                }
            });
        }

        function toggleSilenceDetection(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.regions) {
                var thresholdInput = document.getElementById(`silence-threshold-${index}`);
                var durationInput = document.getElementById(`silence-duration-${index}`);
                var threshold = parseFloat(thresholdInput.value) || -40;
                var duration = parseFloat(durationInput.value) || 0.5;

                if (wavesurfer.isSilenceDetected) {
                    wavesurfer.regions.clear();
                    wavesurfer.isSilenceDetected = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`);
                    if (button) button.classList.remove('active');
                    updateRegionLabel(index, 0);
                } else {
                    wavesurfer.getDecodedData().then(audioBuffer => {
                        const regions = detectSilence(audioBuffer, audioBuffer.sampleRate, threshold, duration);
                        regions.forEach(function(region, idx) {
                            wavesurfer.regions.add({
                                start: region.start,
                                end: region.end,
                                color: 'rgba(0, 255, 0, 0.3)',
                                data: { type: 'silence', index: idx },
                                drag: false,
                                resize: false
                            });
                        });
                    wavesurfer.isSilenceDetected = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`);
                    if (button) button.classList.add('active');
                    updateRegionLabel(index, regions.length);
                }).catch(function() {
                    document.getElementById('error-' + index).textContent = 'Silence detection failed';
                });
            } else {
                document.getElementById('error-' + index).textContent = 'Silence detection unavailable';
            }
        }

        function clearRegions(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.regions) {
                wavesurfer.regions.clear();
                wavesurfer.isSilenceDetected = false;
                var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`);
                if (button) button.classList.remove('active');
                updateRegionLabel(index, 0);
            }
        }

        function toggleEnvelope(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.envelope) {
                if (wavesurfer.isEnvelopeApplied) {
                    wavesurfer.envelope.setFade(0, 0, 0, 0);
                    wavesurfer.isEnvelopeApplied = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`);
                    if (button) button.classList.remove('active');
                } else {
                    wavesurfer.envelope.setFade(2, 0, 2, 0);
                    wavesurfer.isEnvelopeApplied = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`);
                    if (button) button.classList.add('active');
                }
            } else {
                document.getElementById('error-' + index).textContent = 'Envelope unavailable';
            }
        }

        function toggleMinimap(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.minimap) {
                if (wavesurfer.isMinimapVisible) {
                    wavesurfer.minimap.hide();
                    wavesurfer.isMinimapVisible = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .minimap-toggle`);
                    if (button) button.classList.remove('active');
                } else {
                    wavesurfer.minimap.show();
                    wavesurfer.isMinimapVisible = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .minimap-toggle`);
                    if (button) button.classList.add('active');
                }
            } else {
                document.getElementById('error-' + index).textContent = 'Minimap unavailable';
            }
        }

        function toggleSpectrogram(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.spectrogram) {
                if (wavesurfer.isSpectrogramVisible) {
                    wavesurfer.spectrogram.hide();
                    wavesurfer.isSpectrogramVisible = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .spectrogram-toggle`);
                    if (button) button.classList.remove('active');
                } else {
                    wavesurfer.spectrogram.show();
                    wavesurfer.isSpectrogramVisible = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .spectrogram-toggle`);
                    if (button) button.classList.add('active');
                }
            } else {
                document.getElementById('error-' + index).textContent = 'Spectrogram unavailable';
            }
        }

        function toggleTimeline(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.timeline) {
                if (wavesurfer.isTimelineVisible) {
                    wavesurfer.timeline.hide();
                    wavesurfer.isTimelineVisible = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .timeline-toggle`);
                    if (button) button.classList.remove('active');
                } else {
                    wavesurfer.timeline.show();
                    wavesurfer.isTimelineVisible = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .timeline-toggle`);
                    if (button) button.classList.add('active');
                }
            } else {
                document.getElementById('error-' + index).textContent = 'Timeline unavailable';
            }
        }

        function zoomIn(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.zoom) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() * 2);
            } else {
                document.getElementById('error-' + index).textContent = 'Zoom unavailable';
            }
        }

        function zoomOut(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.zoom) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() / 2);
            } else {
                document.getElementById('error-' + index).textContent = 'Zoom unavailable';
            }
        }

        function updateRegionLabel(index, count) {
            var label = document.getElementById(`region-label-${index}`);
            if (label) {
                label.textContent = count > 0 ? `${count} regions detected` : '';
            }
        }

        function renderControlInterface(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            container.innerHTML = '';
            var controlTable = document.createElement("table");
            controlTable.border = "0";
            var headerRow = controlTable.insertRow(0);
            var headerCell = headerRow.insertCell(0);

            var isRecording = jsonObj.app.edit.current_recording && jsonObj.app.edit.current_recording !== "";
            headerCell.innerHTML = `
                <div class="control-surface">
                    <div class="interface-button ${isRecording ? 'stop' : 'start'}">
                        <a href="${isRecording ? '/stop' : '/start'}" id="record-btn">${isRecording ? 'STOP CAPTURE' : 'CAPTURE'}</a>
                    </div>
                    <div class="interface-button ${jsonObj.app.synchronizing ? 'synchronizing' : 'synchronize'}">
                        <a href="/synchronize">SYNCH ${jsonObj.partner || 'N/A'}</a>
                    </div>
                    <div class="interface-button empty"><a href="/empty">CLEAR BIN</a></div>
                </div>`;
            container.appendChild(controlTable);

            setInterval(function() {
                fetch('/status', { cache: 'no-store' }).then(response => {
                    if (!response.ok) throw new Error('Server status ' + response.status);
                    return response.text();
                }).then(html => {
                    var parser = new DOMParser();
                    var doc = parser.parseFromString(html, 'text/html');
                    var newJsonScript = doc.querySelector('script').textContent.match(/var jsonObject = ({.*});/);
                    if (newJsonScript) {
                        var newJson = JSON.parse(newJsonScript[1]);
                        renderControlInterface(newJson, containerId);
                        renderStatus(newJson, 'current-status');
                    }
                }).catch(function() {
                    return document.getElementById('current-status').appendChild('<p class="error-message">Status update failed</p>');
                });
            }, 2000);
        }

        function renderStatus(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            container.innerHTML = '';
            var statusTable = document.createElement("table");
            statusTable.border = "0";
            var headerRow = statusTable.insertRow(0);
            var headerCell = headerRow.insertCell(0);

            document.titleVar = 'CREAM::' + jsonObj.hostname;
            headerCell.innerHTML = jsonObj.app.edit.current_recording ?
                `<h1>BIN:${jsonObj.hostname}</h1> <Var><b>::CAPTURE:</b><pre>${jsonObj.app.edit.current_recording}</pre></h2>` +
                `<h3>Version: ${JSON.stringify(jsonObj.app.version)}</h3>` :
                `<h>BIN:${jsonObj.hostname}</h1> <h2><var>::</h2> <h3>Not currently recording.</h3>` +
                `<h3>Version: ${JSON.stringify(jsonObj.app.version)}</h3>`;
            container.appendChild(statusTable);
        }

        function copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("Copied to clipboard!"));
        }

        function openLink(fileName) {
            window.location.href = '/play/' + encodeURIComponent(fileName);
        }

        if (jsonObject.hostname === "mix-o") {
            document.body.style.backgroundColor = "#8B4000";
        } else if (jsonObject.hostname === "mix-j") {
            document.body.style.backgroundColor = "#083F71";
        } else {
            document.body.style.backgroundColor = "#1b2a3f";
        }

        document.addEventListener('DOMContentLoaded', function() {
            var collapsible = document.querySelector('.collapsible');
            if (collapsible) {
                collapsible.addEventListener('click', toggleContent);
            }
            var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
            tooltipTriggerList.map(function (el) { return new bootstrap.Tooltip(el); });
            waitForPlugins(function() {
                renderStatus(jsonObject, "current-status");
                renderControlInterface(jsonObject, "control-interface");
                prettifyAndRenderJSON(jsonObject, "json-container");
                renderWAVTracks(jsonObject, "wav-files");
            });
        });
    </script>
    <div class="container">
        {{#error}}<div class="alert alert-danger">{{error}}</div>{{/if}}
        {{#message}}<div class="alert alert-success">{{message}}</div>{{/if}}
        <div id="current-status"></div>
        <div id="control-interface"></div>
        <h2>Local Recordings</h2>
        <div id="wav-files"></div>
        <h2>Publish to IPFS</h2>
        <form method="POST" action="/publish">
            <input type="hidden" name="action" value="publish">
            <div class="mb-3">
                <label class="form-label">Select File:</label>
                <select class="form-select" name="filename">
                    {{#wav_files}}
                    <option value="{{.}}">{{.}}</option>
                    {{/wav_files}}
                </select>
            </div>
            <div class="mb-3">
                <label class="form-label">Friendly Name:</label>
                <input type="text" class="form-control" name="friendly_name" pattern="[a-zA-Z0-9_-]+" required>
            </div>
            <div class="mb-3 form-check">
                <input type="checkbox" class="form-check-input" name="pin" value="yes">
                <label class="form-check-label" data-bs-toggle="tooltip" title="Track file availability on your device">Pin to IPFS</label>
            </div>
            <div class="mb-3 form-check">
                <input type="checkbox" class="form-check-input" name="encrypt" id="yes" value="yes">
                <label class="form-check-label" data-bs-toggle="tooltip" title="Encrypt file with unique password">Encrypt File</label>
            </div>
            <button type="submit" class="btn btn-primary">Publish</button>
        </form>
        <h2>Published Files</h2>
        <table class="table table-bordered">
            <thead>
                <tr>
                    <th>Friendly Name</th>
                    <th>Filename</th>
                    <th>Tracks</th>
                    <th>URL</th>
                    <th>Encrypted</th>
                    <th>Password</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                {{#published_files}}
                <tr>
                    <td>{{friendly_name}}</td>
                    <td>{{filename}}</td>
                    <td>{{cid}}</td>
                    <td><a href="{{url}}">{{url}}</td>
                    <td>{{encrypted}}</td>
                    <td>{{password}}</td>
                    <td>
                        <button class="btn btn-sm btn-secondary" onclick="copyToClipboard('{{url}}}')">Copy URL</button>
                        {{#password}}
                        <button class="btn btn-sm btn-secondary" onclick="copyToClipboard('{{password}}')">Copy Password</button>
                    </td>
                </tr>
                {{/#}}
            </tbody>
        </table>
        <p class="text-warning"><strong>WARNING:</strong> If file is encrypted, share password securely!</p>
        <div class="collapsible">::debug::
            <div id="json-container"></div>
        </div>
    </div>
</body>
</html>
]]

local function saveTemplate()
    local file, err = io.open("index.html", "w")
    if not file then
        cLOG(syslog.LOG_ERR, "Failed to open index.html for writing: " .. tostring(err))
        error("Cannot save template: " .. tostring(err))
    end
    local success, write_err = pcall(function() file:write(template) end)
    if not success then
        cLOG(syslog.LOG_ERR, "Failed to write template: " .. tostring(write_err))
    end
    file:close()
end

-- Web Handlers
local StatusHandler = class("StatusHandler", turbo.web.RequestHandler)
function StatusHandler:get()
    local status, result = pcall(function()
        local files = list_files() or {}
        local devices = CREAM.devices or { online = {}, init = function() end }
        devices:init()
        local online = devices.online or {}
        local recording = CREAM.edit.current_recording or ""
        local tracks = CREAM.edit.Tracks or {}
        print("files: ", files)
        print("devices.online: ", online)
        print("recording: ", recording)
        print("tracks: ", tracks)
        local rendered = template
            :gsub("{files}", table.concat(files, "\n"))
            :gsub("{devices}", cjson.encode(online))
            :gsub("{recording}", recording)
            :gsub("{tracks}", cjson.encode(tracks))
        return rendered
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Status handler error: " .. tostring(result) .. " | Type: " .. type(result))
        print("Status handler error: ", tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    else
        self:write(result)
    end
end

function StatusHandler:on_finish()
    collectgarbage("collect")
end

local StartHandler = class("StartHandler", turbo.web.RequestHandler)
function StartHandler:get()
    local status, result = pcall(function()
        if creamIsExecuting then
            cLOG(syslog.LOG_WARNING, "Recording in progress: " .. tostring(CREAM.edit.current_recording))
            self:set_status(400)
            self:write("Recording already in progress")
            return
        end
        CREAM.edit = CREAM.edit or { current_recording = "", Tracks = list_wav_files() }
        CREAM.edit.current_recording = string.format("%s::%s.wav",
            syscall.gethostname(),
            os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)"))
        local command = string.format(
            "/usr/bin/arecord -vvv -f cd -t wav %s%s -D plughw:CARD=MiCreator,DEV=0 2>&1 > %sarecord.log",
            config.CREAM_ARCHIVE_DIRECTORY, CREAM.edit.current_recording, config.CREAM_ARCHIVE_DIRECTORY)
        creamIsExecuting = true
        cLOG(syslog.LOG_INFO, "Starting recording: " .. CREAM.edit.current_recording)
        executeCommand(command, nil, function() return creamIsExecuting end, function(val) creamIsExecuting = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Start handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local StopHandler = class("StopHandler", turbo.web.RequestHandler)
function StopHandler:get()
    local status, result = pcall(function()
        local command = "killall arecord"
        creamIsExecuting = false
        cLOG(syslog.LOG_INFO, "Stopping: " .. tostring(CREAM.edit and CREAM.edit.current_recording or "none"))
        if CREAM.edit then
            CREAM.edit.current_recording = ""
        end
        executeCommand(command, function(result)
            cLOG(syslog.LOG_DEBUG, "Stop command result: ", result)
        end, function() return false end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Stop handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local EmptyHandler = class("EmptyHandler", turbo.web.RequestHandler)
function EmptyHandler:get()
    local status, result = pcall(function()
        local command = string.format("find %s -name '*.wav' -exec rm -rf {} \\;", config.CREAM_ARCHIVE_DIRECTORY)
        creamIsExecuting = false
        cLOG(syslog.LOG_INFO, "Emptying recordings")
        if CREAM.edit then
            CREAM.edit.current_recording = ""
        end
        executeCommand(command, function(result)
            cLOG(syslog.LOG_DEBUG, "Empty command result: ", result)
        end, function() return false end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Empty handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local SynchronizeHandler = class("SynchronizeHandler", turbo.web.RequestHandler)
function SynchronizeHandler:get()
    local status, result = pcall(function()
        if not config.CREAM_SYNC_PARTNER then
            cLOG(syslog.LOG_WARNING, "Synchronization not supported")
            self:write("Synchronization not supported")
            self:set_status(303)
            self:set_header("Location", "/status")
            return
        end
        local command = creamIsSynchronizing and "killall rsync" or string.format(
            "rsync -avz --include='*.wav' ibi@%s.local:%s %s 2>&1 > %srsync.log",
            config.CREAM_SYNC_PARTNER, config.CREAM_ARCHIVE_DIRECTORY,
            config.CREAM_ARCHIVE_DIRECTORY, config.CREAM_ARCHIVE_DIRECTORY)
        creamIsSynchronizing = not creamIsSynchronizing
        cLOG(syslog.LOG_INFO, creamIsSynchronizing and "Starting synchronization" or "Stopping synchronization")
        executeCommand(command, nil, function() return creamIsSynchronizing end, function(val) creamIsSynchronizing = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Synchronize handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local PublishHandler = class("PublishHandler", turbo.web.RequestHandler)
function PublishHandler:post()
    local status, result = pcall(function()
        local filename = self:get_argument("filename")
        local friendly_name = self:get_argument("friendly_name")
        local do_pin = self:get_argument("pin", "no") == "yes"
        local do_encrypt = self:get_argument("encrypt", "no") == "yes"

        if not filename or not friendly_name or friendly_name == "" or not friendly_name:match("^[a-zA-Z0-9-_]+$") then
            self:redirect("/status?error=Invalid%20filename%20or%20friendly%20name")
            return
        end

        local file_path = WAV_DIR .. filename
        local ipfs_status, err = pcall(ensure_ipfs_daemon)
        if not ipfs_status then
            self:redirect("/status?error=IPFS%20failed:%20" .. turbo.escape.encode(err))
            return
        end

        local final_file = file_path
        local password = nil
 if do_encrypt then
            password = generate_password(32)
            final_file = file_path
        end

        local cid, ipfs_err = add_file_to_ipfs(final_file);
        if not cid then
            self:redirect("/status?error=" .. turbo.escape.encode(ipfs_err))
            return
        end

        local url, db_err = store_in_database(filename, friendly_name, cid, do_encrypt, password, "uploaded")
        if not url then
            self:redirect("/status?error=" .. turbo.escape.encode(db_err))
            return
        end

        local message = string.format(
            "File uploaded! CID: %s, URL: %s%s, s",
            cid, url, do_encrypt and ", Password: " .. password or ""
        )
        self:redirect("/status?message=" .. turbo.escape.encode(message))
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Publish handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local PlayHandler = class("PlayHandler", turbo.web.RequestHandler)
function PlayHandler:get(fileToPlay)
    local status, result = pcall(function()
        if not fileToPlay:match("^[a-zA-Z0-9_-.-:.]+::.+%.wav$") then
            cLOG(syslog.LOG_ERR, "Invalid file name: " .. fileToPlay)
            self:set_status(400)
            self:write("Invalid file name")
            return
        end
        local file_path = WAV_DIR .. fileToPlay
        creamIsPlaying = true
        local command = string.format("/usr/bin/aplay %q -d 0 2>&1", file_path)
        cLOG(syslog.LOG_INFO, "Playing: " .. fileToPlay)
        executeCommand(command, nil, function() return creamIsPlaying end, function(val) creamIsPlaying = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Play handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
end

local WavHandler = class("WavHandler", turbo.web.RequestHandler)
function WavHandler:get(wavFile)
    local status, result = pcall(function()
        local wavFilePath = WAV_DIR .. wavFile
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
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "WAV handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
    self:finish()
end

local JsHandler = class("JsHandler", turbo.web.RequestHandler)
function JsHandler:get(jsFile)
    local status, result = pcall(function()
        local jsFilePath = config.CREAM_STATIC_DIRECTORY .. jsFile
        cLOG(syslog.LOG_INFO, "Serving JS file: " .. jsFilePath)
        local file = io.open(jsFilePath, "rb")
        if file then
            local content = file:read("*a")
            file:close()
            self:set_header("Content-Type", "text/javascript")
            self:write(content)
        else
            self:set_status(404)
            self:write("File not found")
        end
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "JS handler error: " .. tostring(result))
        self:set_status(500)
        self:write("Internal server error")
    end
    self:finish()
end

local FaviconHandler = class("FaviconHandler", turbo.web.RequestHandler)
function FaviconHandler:get()
    self:set_status(204)
    self:finish()
end

-- Define application
local app = turbo.web.Application({
    {"/status", StatusHandler},
    {"/start", StartHandler},
    {"/stop", StopHandler},
    {"/empty", EmptyHandler},
    {"/synchronize", SynchronizeHandler},
    {"/publish", PublishHandler},
    {"/play/(.*)$", PlayHandler},
    {"/static/(.*)$", WavHandler},
    {"/js/(.*)$", JsHandler},
    {"/favicon.ico", FaviconHandler}
})

-- Main application
setup_database()
saveTemplate()
if isPortInUse(APP_SERVER_PORT) then
    cLOG(syslog.LOG_ERR, string.format("Port %d is already in use.", APP_SERVER_PORT))
    os.exit(1)
end
CREAM.edit = CREAM.edit or { current_recording = "", Tracks = list_wav_files() }
CREAM:init()

-- Main loop for processing commands and CREAM updates
local function mainLoop()
    while cSTACK:size() > 0 do
        local command = cSTACK:pop()
        if command then
            local status, err = pcall(command)
            if not status then
                cLOG(syslog.LOG_ERR, "Command execution failed: " .. tostring(err))
            end
        end
    end
    if creamIsExecuting then
        local status, _ = pcall(CREAM.update, CREAM)
        if not status then
            cLOG(syslog.LOG_ERR, "CREAM update failed")
        end
    end
    -- Schedule the next iteration
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + COMMAND_INTERVAL, mainLoop)
end

-- Start the main loop and web server
app:listen(APP_SERVER_PORT)
turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic(), mainLoop)
turbo.ioloop.instance():start()
