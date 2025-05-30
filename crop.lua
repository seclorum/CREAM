#!/usr/bin/env luajit

-- Ensure luarocks local path is included
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.luarocks/share/lua/5.1/?.lua"
package.cpath = package.cpath .. ";" .. os.getenv("HOME") .. "/.luarocks/lib/lua/5.1/?.so"

-- Import required modules
local turbo = require("turbo") -- TurboLua web framework
local sqlite3 = require("lsqlite3") -- SQLite database support
local lfs = require("lfs") -- LuaFileSystem for directory listing
local cjson = require("cjson") -- JSON encoding/decoding

-- Configuration
local IPFS_GATEWAY = "https://ipfs.io/ipfs/" -- IPFS gateway URL
local DB_NAME = "/opt/austrianAudio/var/ipfs_wavs.db" -- SQLite database path
local WAV_DIR = "/home/user/wavs" -- Directory for .wav files
local APP_NAME = "CROP" -- Application name
local APP_SERVER_PORT = 8080 -- Server port
local COMMAND_INTERVAL = 100 -- Command loop interval (ms)
local ARCHIVE_DIRECTORY = WAV_DIR .. "/" -- Directory for recordings

-- Global state variables
local isRecording = false -- Tracks if a recording is in progress
local isPlaying = false -- Tracks if audio playback is active

-- Logging utility function
local function cLOG(level, ...)
    local message = table.concat({...}, " ") -- Concatenate log message arguments
    print(string.format("LOG:%d %s", level, message)) -- Print to console
end

-- Check if port is in use
local function isPortInUse(port)
    local server = turbo.tcpserver.TCPServer()
    local result, err = pcall(function()
        server:bind("0.0.0.0", port)
        server:close()
    end)
    if result then
        return false
    end
    cLOG(6, "Port check error: " .. tostring(err)) -- LOG_DEBUG equivalent
    return true
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
    local status, err = pcall(function() db:exec(query) end)
    db:close()
    if not status then
        error("Error creating database: " .. err)
    end
end

-- Execute shell command
local function execute_command(cmd)
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Check and start IPFS daemon
local function ensure_ipfs_daemon()
    local check = execute_command("pgrep ipfs")
    if check == "" then
        execute_command("ipfs daemon &")
        turbo.util.sleep(5000) -- Wait for daemon to start
    end
    local response = execute_command("curl -s http://localhost:5001/api/v0/id")
    if response == "" then
        error("IPFS daemon not responding")
    end
end

-- Generate secure password (placeholder; implement with a crypto library if needed)
local function generate_password(length)
    return "placeholder_password_" .. os.time() -- Replace with secure random generation
end

-- Store file metadata
local function store_in_database(filename, friendly_name, cid, encrypted, password, status)
    local encoded_filename = filename:gsub("([^%w ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+")
    local url = cid and (IPFS_GATEWAY .. cid .. "?filename=" .. encoded_filename) or ""

    local db = sqlite3.open(DB_NAME)
    local stmt
    if encrypted and password then
        stmt = db:prepare[[
            INSERT INTO files (filename, friendly_name, cid, url, encrypted, password, status)
            VALUES (:filename, :friendly_name, :cid, :url, :encrypted, :password, :status)
        ]]
        stmt:bind_names{
            filename = filename,
            friendly_name = friendly_name,
            cid = cid or "",
            url = url,
            encrypted = 1,
            password = password,
            status = status
        }
    else
        stmt = db:prepare[[
            INSERT INTO files (filename, friendly_name, cid, url, encrypted, password, status)
            VALUES (:filename, :friendly_name, :cid, :url, :encrypted, NULL, :status)
        ]]
        stmt:bind_names{
            filename = filename,
            friendly_name = friendly_name,
            cid = cid or "",
            url = url,
            encrypted = 0,
            status = status
        }
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
    for row in db:nrows("SELECT id, filename, friendly_name, cid, url, encrypted, password, status FROM files") do
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

-- Record audio
local function record_audio()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local file_path = string.format("%s/recording_%s.wav", WAV_DIR, timestamp)
    local cmd = string.format("arecord -f cd -t wav %q -D plughw:CARD=MiCreator,DEV=0", file_path)
    execute_command(cmd)
    return file_path
end

-- Play audio
local function play_audio(file_path)
    local cmd = string.format("/usr/bin/aplay %q -d 0", file_path)
    execute_command(cmd)
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
    local output = execute_command(cmd)
    local cid = output:match("added (%S+)")
    if not cid then
        return nil, "Error: Failed to get CID from IPFS."
    end
    if do_pin then
        local pin_cmd = string.format("ipfs pin add %q", cid)
        execute_command(pin_cmd)
    end
    return cid
end

-- Initialize application
local cSTACK = turbo.structs.deque:new()
cSTACK:append(function()
    local hostname = execute_command("hostname"):gsub("\n", "")
    cLOG(6, string.format("%s running on host: %s on port %d", APP_NAME, hostname, APP_SERVER_PORT))
end)

-- TurboLua Handlers
local MainHandler = class("MainHandler", turbo.web.RequestHandler)

function MainHandler:get()
    local wav_files = list_wav_files()
    local published_files = list_files()
    local hostname = execute_command("hostname"):gsub("\n", "")
    local userData = {
        hostname = hostname,
        app = {
            recording = isRecording,
            name = APP_NAME,
            edit = { current_recording = isRecording and "recording" or "", Tracks = wav_files }
        }
    }
    local jsonData = cjson.encode(userData)
    self:render("index.html", {
        wav_files = wav_files,
        published_files = published_files,
        message = self:get_argument("message", nil),
        error = self:get_argument("error", nil),
        hostname = hostname,
        jsonData = jsonData,
        app = userData.app
    })
end

function MainHandler:post()
    local action = self:get_argument("action")
    if action == "record_start" then
        if isRecording then
            self:redirect("/?error=Recording%20already%20in%20progress")
            return
        end
        isRecording = true
        record_audio()
        isRecording = false
        local message = "Recording saved"
        self:redirect("/?message=" .. turbo.escape.escape(message))
        return
    elseif action == "publish" then
        local filename = self:get_argument("filename")
        local friendly_name = self:get_argument("friendly_name")
        local do_pin = self:get_argument("pin", "no") == "yes"
        local do_encrypt = self:get_argument("encrypt", "no") == "yes"

        if not filename or not friendly_name or friendly_name == "" or not friendly_name:match("^[a-zA-Z0-9-_]+$") then
            self:redirect("/?error=Invalid%20filename%20or%20friendly%20name")
            return
        end

        local file_path = WAV_DIR .. "/" .. filename
        local status, err = pcall(ensure_ipfs_daemon)
        if not status then
            self:redirect("/?error=IPFS%20daemon%20failed:%20" .. turbo.escape.escape(err))
            return
        end

        local final_file = file_path
        local password = nil
        if do_encrypt then
            password = generate_password(32)
            final_file = file_path -- Placeholder; implement encryption if needed
        end

        local cid, ipfs_err = add_file_to_ipfs(final_file, do_pin)
        if not cid then
            self:redirect("/?error=" .. turbo.escape.escape(ipfs_err))
            return
        end

        local url, db_err = store_in_database(filename, friendly_name, cid, do_encrypt, password, "uploaded")
        if not url then
            self:redirect("/?error=" .. turbo.escape.escape(db_err))
            return
        end

        local message = string.format(
            "File uploaded! CID: %s, URL: %s%s",
            cid, url, do_encrypt and ", Password: " .. password or ""
        )
        self:redirect("/?message=" .. turbo.escape.escape(message))
    end
end

local PlayHandler = class("PlayHandler", turbo.web.RequestHandler)
function PlayHandler:get(fileToPlay)
    if not fileToPlay:match("^[a-zA-Z0-9%-:_.]+%.wav$") then
        cLOG(3, "Invalid file name: " .. fileToPlay) -- LOG_ERR equivalent
        self:set_status(400)
        self:write("Invalid file name")
        return
    end
    local file_path = WAV_DIR .. "/" .. fileToPlay
    isPlaying = true
    play_audio(file_path)
    isPlaying = false
    self:set_status(303)
    self:set_header("Location", "/")
    self:finish()
end

local WavHandler = class("WavHandler", turbo.web.RequestHandler)
function WavHandler:get(wavFile)
    local wavFilePath = WAV_DIR .. "/" .. wavFile
    cLOG(6, "Serving WAV file: " .. wavFilePath)
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

-- Mustache template
local template = [[
<!DOCTYPE html>
<html>
<head>
    <title>CROP: Audio Recorder & IPFS Publisher</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js"></script>
    <script src="https://unpkg.com/wavesurfer.js@7/dist/plugins/envelope.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #1b2a3f; color: white; }
        .waveform-container { height: 100px; margin: 10px 0; background-color: #222; border: 1px solid #444; }
        .waveform-controls { display: flex; gap: 5px; flex-wrap: wrap; }
        .waveform-button { padding: 5px 10px; background-color: #555; color: white; border: none; border-radius: 3px; cursor: pointer; }
        .waveform-button:hover { background-color: #777; }
        .waveform-button.active { background-color: #4CAF50; }
        .error-message { color: red; font-size: 12px; }
        .interface-button { padding: 10px 20px; margin: 10px; font-size: 16px; cursor: pointer; border: 2px solid #fff; border-radius: 5px; background-color: #444; color: #fff; }
        .interface-button:hover { background-color: #fff; color: #333; }
        .start { background-color: #A7F9AB; border-color: #4CAF50; }
        .stop { background-color: #FBB1AB; border-color: #f44336; }
    </style>
    <script>
        function copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert("Copied to clipboard!"));
        }
        function startRecording() {
            fetch("/", { method: "POST", body: new URLSearchParams({ action: "record_start" }) })
                .then(() => location.reload());
        }
        window.wavesurfers = [];
        function renderWAVTracks(tracks, containerId) {
            console.log('Rendering tracks at ' + new Date().toISOString());
            var container = document.getElementById(containerId);
            container.innerHTML = '';
            var wavTable = document.createElement("table");
            wavTable.border = "0";
            var waveformData = [];
            tracks.forEach(function(track, i) {
                var row = wavTable.insertRow(0);
                var cell = row.insertCell(0);
                var waveformId = 'waveform-' + i;
                cell.innerHTML = `
                    <div>
                        <a href="/play/${track}">${track}</a>
                        <div id="${waveformId}" class="waveform-container"></div>
                        <div class="waveform-controls">
                            <button class="waveform-button" onclick="wavesurfers[${i}]?.playPause()">Play/Pause</button>
                            <button class="waveform-button envelope-toggle" onclick="toggleEnvelope(${i})">Toggle Envelope</button>
                            <span class="error-message" id="error-${i}"></span>
                        </div>
                    </div>`;
                waveformData.push({ index: i, waveformId: waveformId, track: track });
            });
            container.appendChild(wavTable);
            waveformData.forEach(function(data) {
                try {
                    var wavesurfer = WaveSurfer.create({
                        container: '#' + data.waveformId,
                        waveColor: 'violet',
                        progressColor: 'purple',
                        height: 100,
                        responsive: true,
                        plugins: [
                            WaveSurfer.envelope ? WaveSurfer.envelope.create({ volume: 1.0 }) : null
                        ].filter(p => p)
                    });
                    wavesurfer.load('/static/' + data.track);
                    wavesurfer.on('ready', function() {
                        console.log('Waveform ' + data.index + ' ready at ' + new Date().toISOString());
                        window.wavesurfers[data.index] = wavesurfer;
                        wavesurfer.isEnvelopeApplied = false;
                    });
                    wavesurfer.on('error', function(e) {
                        document.getElementById('error-' + data.index).textContent = 'Error: ' + e.message;
                    });
                    window.wavesurfers[data.index] = wavesurfer;
                } catch (e) {
                    console.error('WaveSurfer init error for ' + data.track + ':', e);
                    document.getElementById('error-' + data.index).textContent = 'Failed to load waveform: ' + e.message;
                }
            });
        }
        function toggleEnvelope(index) {
            console.log('Toggling envelope for index ' + index + ' at ' + new Date().toISOString());
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.envelope) {
                wavesurfer.isEnvelopeApplied = !wavesurfer.isEnvelopeApplied;
                wavesurfer.envelope.setFade(wavesurfer.isEnvelopeApplied ? 2 : 0, 0, wavesurfer.isEnvelopeApplied ? 2 : 0, 0);
                var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`);
                if (button) button.classList.toggle('active', wavesurfer.isEnvelopeApplied);
            } else {
                document.getElementById('error-' + index).textContent = 'Envelope unavailable: Plugin not loaded';
            }
        }
        document.addEventListener('DOMContentLoaded', function() {
            console.log('DOM content loaded at ' + new Date().toISOString());
            var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
            tooltipTriggerList.map(function (tooltipTriggerEl) { return new bootstrap.Tooltip(tooltipTriggerEl); });
            var tracks = {{{app.edit.Tracks}}};
            renderWAVTracks(tracks, 'wav-tracks');
        });
    </script>
</head>
<body>
    <div class="container">
        <h1>CROP: Audio Recorder & IPFS Publisher</h1>
        {{#error}}<div class="alert alert-danger">{{error}}</div>{{/error}}
        {{#message}}<div class="alert alert-success">{{message}}</div>{{/message}}
        <div id="current-status">
            <h2>Status: {{hostname}}</h2>
            {{#app.recording}}
            <p><b>CAPTURING:</b> Recording in progress...</p>
            {{else}}
            <p>Not currently recording.</p>
            {{/app.recording}}
        </div>
        <div id="control-interface">
            <button class="interface-button {{#app.recording}}stop{{else}}start{{/app.recording}}" onclick="startRecording()">
                {{#app.recording}}STOP CAPTURE{{else}}CAPTURE{{/app.recording}}
            </button>
        </div>
        <h2>Local Recordings</h2>
        <div id="wav-tracks"></div>
        <h2>Publish to IPFS</h2>
        <form method="POST" action="/">
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
                <input type="text" class="form-control" name="friendly_name" pattern="[a-zA-Z0-9-_]+" required>
            </div>
            <div class="mb-3 form-check">
                <input type="checkbox" class="form-check-input" name="pin" value="yes">
                <label class="form-check-label" data-bs-toggle="tooltip" title="Keep the file available on your device">Pin to IPFS</label>
            </div>
            <div class="mb-3 form-check">
                <input type="checkbox" class="form-check-input" name="encrypt" value="yes">
                <label class="form-check-label" data-bs-toggle="tooltip" title="Encrypt the file with a unique password">Encrypt File</label>
            </div>
            <button type="submit" class="btn btn-primary">Publish</button>
        </form>
        <h2>Published Files</h2>
        <table class="table table-bordered">
            <thead>
                <tr>
                    <th>Friendly Name</th>
                    <th>Filename</th>
                    <th>CID</th>
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
                    <td><a href="{{url}}">{{url}}</a></td>
                    <td>{{encrypted}}</td>
                    <td>{{password}}</td>
                    <td>
                        <button class="btn btn-sm btn-secondary" onclick="copyToClipboard('{{url}}')">Copy URL</button>
                        {{#password}}
                        <button class="btn btn-sm btn-secondary" onclick="copyToClipboard('{{password}}')">Copy Password</button>
                        {{/password}}
                    </td>
                </tr>
                {{/published_files}}
            </tbody>
        </table>
        <p class="text-warning"><strong>WARNING:</strong> If a file is encrypted, share the password securely via a separate channel!</p>
    </div>
</body>
</html>
]]

-- Save template
local function save_template()
    local file = io.open("index.html", "w")
    file:write(template)
    file:close()
end

-- Main application
setup_database()
save_template()
if isPortInUse(APP_SERVER_PORT) then
    cLOG(3, string.format("Port %d is already in use.", APP_SERVER_PORT))
    os.exit(1)
end
local app = turbo.web.Application({
    {"^/$", MainHandler},
    {"/play/(.*)$", PlayHandler},
    {"^/static/(.*)$", WavHandler}
})
app:listen(APP_SERVER_PORT)
local function main_loop()
    while cSTACK:size() > 0 do
        local command = cSTACK:pop()
        if command then
            local status, err = pcall(command)
            if not status then
                cLOG(3, "Command execution failed: " .. tostring(err))
            end
        end
    end
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + COMMAND_INTERVAL, main_loop)
end
turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + COMMAND_INTERVAL, main_loop)
turbo.ioloop.instance():start()
