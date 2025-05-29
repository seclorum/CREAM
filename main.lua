-- Import required modules
local config = require("config") -- Configuration module for application settings
local turbo = require("turbo") -- TurboLua web framework
local turbo_thread = require("turbo.thread") -- Threading support for TurboLua
local io = require("io") -- Standard I/O library
local posix = require("posix") -- POSIX system calls
local syslog = require("posix.syslog") -- System logging
local cjson = require("cjson") -- JSON encoding/decoding
local syscall = require("syscall") -- System call utilities
local socket = require("socket") -- For port availability checking

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

-- Load CREAM module
local CREAM = require("cream") -- Core CREAM module for audio handling

-- Initialize command stack
local cSTACK = turbo.structs.deque:new() -- Command queue for initialization tasks

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

-- Initialize application
cSTACK:append(function()
    local hostname = syscall.gethostname() -- Get hostname
    config.dump() -- Dump configuration for debugging
    syslog.setlogmask(syslog.LOG_DEBUG) -- Set syslog debug level
    syslog.openlog(config.APP_NAME, syslog.LOG_SYSLOG) -- Initialize syslog
    cLOG(syslog.LOG_INFO, string.format("%s running on host: %s protocol version %s on %s:%d",
        config.APP_NAME, hostname, config.CREAM_PROTOCOL_VERSION,
        config.CREAM_APP_SERVER_HOST, config.CREAM_APP_SERVER_PORT)) -- Log startup info
    cLOG(syslog.LOG_INFO, config.CREAM_APP_VERSION) -- Log application version

    -- Initialize CREAM with error handling
    local status, err = pcall(function()
        CREAM.devices = CREAM.devices or { online = {}, init = function() end, dump = function() end }
        CREAM.devices:init() -- Initialize audio devices
        CREAM.devices:dump() -- Dump device info
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Failed to initialize CREAM devices: " .. tostring(err) .. "\nStack: " .. debug.traceback())
    end
end)

-- Mustache template for the status page
local statusTemplate = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CREAM::{{hostname}}</title>
    <!-- Load WaveSurfer.js and plugins from local static directory -->
    <script src="/js/wavesurfer.js"></script>
    <script src="/js/regions.min.js"></script>
    <script src="/js/envelope.min.js"></script>
    <script src="/js/hover.min.js"></script>
    <script src="/js/minimap.min.js"></script>
    <script src="/js/spectrogram.min.js"></script>
    <script src="/js/timeline.min.js"></script>
    <script src="/js/zoom.min.js"></script>
    <style>
        body {
            font-family: 'Courier New', monospace;
            background-color: {{backgroundColor}}; /* Dynamic background based on hostname */
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
        .waveform-button:hover {
            background-color: #777;
        }
        .waveform-button.active {
            background-color: #4CAF50; /* Green when active */
        }
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
        .ws-region {
            background: rgba(0, 255, 0, 0.3); /* Green tint for silent regions */
        }
        .ws-minimap {
            margin-top: 5px;
            background-color: #333;
            border: 1px solid #444;
        }
        .ws-spectrogram {
            margin-top: 5px;
        }
        .ws-timeline {
            margin-top: 5px;
        }
        .ws-hover {
            background: rgba(255, 255, 255, 0.2); /* Light cursor for hover */
        }
    </style>
</head>
<body>
    <script>
        // Toggle debug JSON container visibility
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

        var jsonObject = {{{jsonData}}}; // JSON data from server

        // Render JSON data with syntax highlighting
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

        // Custom silence detection using audio buffer
        function detectSilence(audioBuffer, sampleRate, threshold, minSilenceDuration) {
            const samples = audioBuffer.getChannelData(0); // Use first channel
            const minSamples = minSilenceDuration * sampleRate; // Convert duration to samples
            const regions = [];
            let silenceStart = null;
            const thresholdAmplitude = Math.pow(10, threshold / 20); // Convert dB to amplitude

            for (let i = 0; i < samples.length; i++) {
                const amplitude = Math.abs(samples[i]);
                if (amplitude < thresholdAmplitude) {
                    if (silenceStart === null) {
                        silenceStart = i; // Start of silence
                    }
                } else {
                    if (silenceStart !== null && (i - silenceStart) >= minSamples) {
                        regions.push({
                            start: silenceStart / sampleRate,
                            end: i / sampleRate
                        }); // Add silence region
                    }
                    silenceStart = null;
                }
            }
            if (silenceStart !== null && (samples.length - silenceStart) >= minSamples) {
                regions.push({
                    start: silenceStart / sampleRate,
                    end: samples.length / sampleRate
                }); // Add final silence region
            }
            return regions;
        }

        // Render waveform tracks with all plugins
        function renderWAVTracks(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            container.innerHTML = '';
            var tracks = (jsonObj.app.edit.Tracks || []).sort(); // Sort tracks alphabetically
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

                // HTML for each track with waveform and controls
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
                    </div></li>`;

                waveformData.push({ index: i, waveformId: waveformId, track: track });
            });

            container.appendChild(wavTable);

            window.wavesurfers = window.wavesurfers || [];
            waveformData.forEach(function(data) {
                try {
                    // Initialize WaveSurfer with all plugins
                    var wavesurfer = WaveSurfer.create({
                        container: '#' + data.waveformId,
                        waveColor: 'violet',
                        progressColor: 'purple',
                        height: 100,
                        responsive: true,
                        backend: 'MediaElement',
                        plugins: [
                            WaveSurfer.regions.create(), // Regions for marking and playing segments
                            WaveSurfer.envelope.create({
                                volume: 1.0, // Default volume
                                fadeInStart: 0,
                                fadeInEnd: 0,
                                fadeOutStart: 0,
                                fadeOutEnd: 0
                            }), // Envelope for volume control
                            WaveSurfer.hover.create({
                                lineColor: '#fff',
                                lineWidth: 2,
                                labelBackground: '#555',
                                labelColor: '#fff'
                            }), // Hover cursor with time
                            WaveSurfer.minimap.create({
                                height: 30,
                                waveColor: '#ddd',
                                progressColor: '#999'
                            }), // Minimap for overview
                            WaveSurfer.spectrogram.create({
                                container: '#' + data.waveformId + '-spectrogram',
                                fftSamples: 512,
                                labels: true
                            }), // Spectrogram for frequency visualization
                            WaveSurfer.timeline.create({
                                container: '#' + data.waveformId + '-timeline'
                            }), // Timeline for time axis
                            WaveSurfer.zoom.create({
                                zoom: 100 // Pixels per second
                            }) // Zoom functionality
                        ]
                    });

                    // Create containers for spectrogram and timeline
                    var waveformContainer = document.getElementById(data.waveformId);
                    var spectrogramDiv = document.createElement('div');
                    spectrogramDiv.id = data.waveformId + '-spectrogram';
                    spectrogramDiv.className = 'ws-spectrogram';
                    waveformContainer.parentNode.insertBefore(spectrogramDiv, waveformContainer.nextSibling);
                    var timelineDiv = document.createElement('div');
                    timelineDiv.id = data.waveformId + '-timeline';
                    timelineDiv.className = 'ws-timeline';
                    waveformContainer.parentNode.insertBefore(timelineDiv, spectrogramDiv.nextSibling);

                    wavesurfer.load('/static/' + data.track); // Load audio file

                    // Initialize plugin states
                    wavesurfer.on('ready', function() {
                        window.wavesurfers[data.index] = wavesurfer;
                        wavesurfer.isSilenceDetected = false;
                        wavesurfer.isMinimapVisible = true;
                        wavesurfer.isSpectrogramVisible = false;
                        wavesurfer.isTimelineVisible = false;
                        wavesurfer.isEnvelopeApplied = false;
                        wavesurfer.spectrogram.hide(); // Hide spectrogram by default
                        wavesurfer.timeline.hide(); // Hide timeline by default
                    });

                    // Play region on click
                    wavesurfer.on('region-click', function(region) {
                        wavesurfer.play(region.start, region.end);
                    });

                    // Update region count label
                    wavesurfer.on('region-created', function() {
                        updateRegionLabel(data.index, Object.keys(wavesurfer.regions.list).length);
                    });

                    // Log errors
                    wavesurfer.on('error', function(e) {
                        console.error('WaveSurfer error for ' + data.track + ':', e);
                    });

                    window.wavesurfers[data.index] = wavesurfer;
                } catch (e) {
                    console.error('Failed to initialize WaveSurfer for ' + data.track + ':', e);
                }
            });
        }

        // Toggle silence detection
        function toggleSilenceDetection(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
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
                    }).catch(e => {
                        console.error('Silence detection failed for waveform ' + index + ':', e);
                    });
                }
            }
        }

        // Clear all regions
        function clearRegions(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
                wavesurfer.regions.clear();
                wavesurfer.isSilenceDetected = false;
                var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`);
                if (button) button.classList.remove('active');
                updateRegionLabel(index, 0);
            }
        }

        // Toggle envelope (fade-in/out)
        function toggleEnvelope(index) {
            var wavesurfer = window.wavesurfer[index];
            if (wavesurfer) {
                if (wavesurfer.isEnvelopeApplied) {
                    wavesurfer.envelope.setFade(0, 0, 0, 0); // Remove envelope
                    wavesurfer.isEnvelopeApplied = false;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`);
                    if (button) button.classList.remove('active');
                } else {
                    // Apply a simple fade-in/fade-out (2 seconds each)
                    wavesurfer.envelope.setFade(2, 0, 2, 0);
                    wavesurfer.isEnvelopeApplied = true;
                    var button = document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`);
                    if (button) button.classList.add('active');
                }
            }
        }

        // Toggle minimap visibility
        function toggleMinimap(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
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
            }
        }

        // Toggle spectrogram visibility
        function toggleSpectrogram(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
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
            }
        }

        // Toggle timeline visibility
        function toggleTimeline(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
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
            }
        }

        // Zoom in
        function zoomIn(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() * 2);
            }
        }

        // Zoom out
        function zoomOut(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() / 2);
            }
        }

        // Update region count label
        function updateRegionLabel(index, count) {
            var label = document.getElementById(`region-label-${index}`);
            if (label) {
                label.textContent = count > 0 ? `${count} silent regions detected` : '';
            }
        }

        // Render control interface (Capture, Sync, Clear)
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
                        <a href="${isRecording ? '/stop' : '/start'}" id="capture-btn">${isRecording ? 'STOP CAPTURE' : 'CAPTURE'}</a>
                    </div>
                    <div class="interface-button ${jsonObj.app.synchronizing ? 'synchronizing' : 'synchronize'}">
                        <a href="/synchronize">SYNCH ${jsonObj.partner} BIN</a>
                    </div>
                    <div class="interface-button empty"><a href="/empty">CLEAR BIN</a></div>
                </div>`;
            container.appendChild(controlTable);

            // Poll /status every 2 seconds to update UI
            setInterval(function() {
                fetch('/status').then(response => response.text()).then(html => {
                    var parser = new DOMParser();
                    var doc = parser.parseFromString(html, 'text/html');
                    var newJsonScript = doc.querySelector('script').textContent.match(/var jsonObject = ({.*});/);
                    if (newJsonScript) {
                        var newJson = JSON.parse(newJsonScript[1]);
                        renderControlInterface(newJson, containerId);
                        renderStatus(newJson, 'current-status');
                    }
                }).catch(err => console.error('Status poll failed:', err));
            }, 2000);
        }

        // Render status (recording state)
        function renderStatus(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            container.innerHTML = '';
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

        // Handle track link clicks
        function openLink(fileName) {
            alert("Opening link: " + fileName);
        }

        // Set background color based on hostname
        if (jsonObject.hostname === "mix-o") {
            document.body.style.backgroundColor = "#8B4000";
        } else if (jsonObject.hostname === "mix-j") {
            document.body.style.backgroundColor = "#083F71";
        } else {
            document.body.style.backgroundColor = "#1b2a3f";
        }

        // Initialize UI on page load
        document.addEventListener('DOMContentLoaded', function() {
            var collapsible = document.querySelector('.collapsible');
            if (collapsible) {
                collapsible.addEventListener('click', toggleContent);
            }
            renderStatus(jsonObject, "current-status");
            renderControlInterface(jsonObject, "control-interface");
            prettifyAndRenderJSON(jsonObject, "json-container");
            renderWAVTracks(jsonObject, "wav-tracks");
        });
    </script>
    <div id="current-status"></div>
    <div id="control-interface"></div>
    <div id="wav-tracks"></div>
    <div class="collapsible">::debug::
        <div id="json-container"></div>
    </div>
</body>
</html>
]]

-- Utility function to execute shell commands
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

-- JavaScript Handler
local creamJsHandler = class("creamJsHandler", turbo.web.RequestHandler)
function creamJsHandler:get(jsFile)
    local status, result = pcall(function()
        local jsFilePath = config.CREAM_STATIC_DIRECTORY .. jsFile
        cLOG(syslog.LOG_INFO, "Serving JS file: " .. jsFilePath)
        local file = io.open(jsFilePath, "rb")
        if file then
            local content = file:read("*a")
            file:close()
            self:set_header("Content-Type", "text/javascript") -- Ensure correct MIME type
            self:write(content)
        else
            self:set_status(404)
            self:write("File not found")
        end
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "JS handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
    self:finish()
end

-- Web Handlers
local creamWebStatusHandler = class("creamWebStatusHandler", turbo.web.RequestHandler)
function creamWebStatusHandler:get()
    local status, result = pcall(function()
        local hostname = syscall.gethostname()
        local userData = {
            hostname = hostname,
            partner = config.CREAM_SYNC_PARTNER or "none",
            backgroundColor = hostname == "mix-o" and "#8B4000" or hostname == "mix-j" and "#083F71" or "#1b2a3f",
            app = {
                recording = creamIsExecuting,
                synchronizing = creamIsSynchronizing,
                name = config.APP_NAME,
                version = config.CREAM_APP_VERSION,
                edit = CREAM.edit or { current_recording = "", Tracks = {} },
                io = CREAM.devices and CREAM.devices.online or {}
            }
        }
        local updateStatus, updateErr = pcall(CREAM.update, CREAM)
        if not updateStatus then
            cLOG(syslog.LOG_ERR, "CREAM update failed: " .. tostring(updateErr) .. "\nStack: " .. debug.traceback())
        end
        cLOG(syslog.LOG_DEBUG, "Rendering /status with current_recording: " .. tostring(userData.app.edit.current_recording) .. ", creamIsExecuting: " .. tostring(creamIsExecuting))
        local jsonData = cjson.encode(userData)
        local rendered = turbo.web.Mustache.render(statusTemplate, {
            hostname = userData.hostname,
            backgroundColor = userData.backgroundColor,
            jsonData = jsonData,
            app = userData.app,
            partner = userData.partner
        })
        return rendered
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Status handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        return self:write("Internal server error")
    end
    self:write(result)
    self:finish()
end
function creamWebStatusHandler:on_finish()
    collectgarbage("collect") -- Clean up memory
end

local creamWebStartHandler = class("creamWebStartHandler", turbo.web.RequestHandler)
function creamWebStartHandler:get()
    local status, result = pcall(function()
        if creamIsExecuting then
            cLOG(syslog.LOG_WARNING, "Recording already in progress: " .. tostring(CREAM.edit.current_recording))
            self:write("Recording already in progress: " .. tostring(CREAM.edit.current_recording))
            return
        end
        -- Ensure CREAM.edit is initialized
        CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
        CREAM.edit.current_recording = string.format("%s::%s.wav",
            syscall.gethostname(),
            os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)"))
        local command = string.format(
            "/usr/bin/arecord -vvv -f cd -t wav %s%s -D plughw:CARD=MiCreator,DEV=0 2>&1 > %sarecord.log",
            config.CREAM_ARCHIVE_DIRECTORY, CREAM.edit.current_recording, config.CREAM_ARCHIVE_DIRECTORY)
        creamIsExecuting = true
        cLOG(syslog.LOG_INFO, "Starting recording: " .. CREAM.edit.current_recording .. ", creamIsExecuting: " .. tostring(creamIsExecuting))
        executeCommand(command, nil, function() return creamIsExecuting end, function(val) creamIsExecuting = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Start handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
end

local creamWebStopHandler = class("creamWebStopHandler", turbo.web.RequestHandler)
function creamWebStopHandler:get()
    local status, result = pcall(function()
        local command = "killall arecord"
        creamIsExecuting = false
        cLOG(syslog.LOG_INFO, "Stopping recording: " .. tostring(CREAM.edit and CREAM.edit.current_recording or "none"))
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
        cLOG(syslog.LOG_ERR, "Stop handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
end

local creamWebEmptyHandler = class("creamWebEmptyHandler", turbo.web.RequestHandler)
function creamWebEmptyHandler:get()
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
        cLOG(syslog.LOG_ERR, "Empty handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
end

local creamWebSynchronizeHandler = class("creamWebSynchronizeHandler", turbo.web.RequestHandler)
function creamWebSynchronizeHandler:get()
    local status, result = pcall(function()
        if not config.CREAM_SYNC_PARTNER then
            cLOG(syslog.LOG_WARNING, "Synchronization not supported on this host")
            self:write("Synchronization not supported")
            self:set_status(303)
            self:set_header("Location", "/status")
            return
        end
        local command = creamIsSynchronizing and "killall rsync" or string.format(
            "rsync -avz --include='%s' ibi@%s.local:%s %s 2>&1 > %srsync.log",
            config.CREAM_SYNC_PARTNER, config.CREAM_SYNC_PARTNER, config.CREAM_ARCHIVE_DIRECTORY,
            config.CREAM_ARCHIVE_DIRECTORY, config.CREAM_ARCHIVE_DIRECTORY)
        creamIsSynchronizing = not creamIsSynchronizing
        cLOG(syslog.LOG_INFO, creamIsSynchronizing and "Starting synchronization" or "Stopping synchronization")
        executeCommand(command, nil, function() return creamIsSynchronizing end, function(val) creamIsSynchronizing = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Synchronize handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
end

local creamWebPlayHandler = class("creamWebPlayHandler", turbo.web.RequestHandler)
function creamWebPlayHandler:get(fileToPlay)
    local status, result = pcall(function()
        -- Strict file name validation
        if not fileToPlay:match("^[a-zA-Z0-9%-:_.]+%.wav$") then
            cLOG(syslog.LOG_ERR, "Invalid file name: " .. fileToPlay)
            self:set_status(400)
            self:write("Invalid file name")
            return
        end
        local command = string.format("/usr/bin/aplay %s%s -d 0 2>&1",
            config.CREAM_ARCHIVE_DIRECTORY, fileToPlay)
        creamIsPlaying = true
        cLOG(syslog.LOG_INFO, "Playing: " .. fileToPlay)
        executeCommand(command, nil, function() return creamIsPlaying end, function(val) creamIsPlaying = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
        self:finish()
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "Play handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end
end

local creamWebRecordStartHandler = class("creamWebRecordStartHandler", turbo.web.RequestHandler)
function creamWebRecordStartHandler:get()
    self:set_status(200)
    self:finish()
end

local creamWebRecordStopHandler = class("creamWebRecordStopHandler", turbo.web.RequestHandler)
function creamWebRecordStopHandler:get()
    self:set_status(200)
    self:finish()
end

local creamWavHandler = class("creamWavHandler", turbo.web.RequestHandler)
function creamWavHandler:get(wavFile)
    local status, result = pcall(function()
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
    end)
    if not status then
        cLOG(syslog.LOG_ERR, "WAV handler error: " .. tostring(result) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
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
    {"^/js/(.*)$", creamJsHandler}
})

-- Initialize CREAM and start server
local status, err = pcall(function()
    CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
    CREAM:init()
end)
if not status then
    cLOG(syslog.LOG_ERR, "CREAM initialization failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
end

-- Check port availability before binding
if isPortInUse(config.CREAM_APP_SERVER_PORT) then
    cLOG(syslog.LOG_ERR, string.format("Port %d is already in use. Please stop other processes or change CREAM_APP_SERVER_PORT.", config.CREAM_APP_SERVER_PORT))
    os.exit(1)
end

creamWebApp:listen(config.CREAM_APP_SERVER_PORT)

-- Main loop for processing command stack
local function creamMain()
    while cSTACK:size() > 0 do
        local command = cSTACK:pop()
        if command then
            local status, err = pcall(command)
            if not status then
                cLOG(syslog.LOG_ERR, "Command execution failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
            end
        end
        if creamIsExecuting then
            local status, err = pcall(CREAM.update, CREAM)
            if not status then
                cLOG(syslog.LOG_ERR, "CREAM update failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
            end
        end
    end
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
end

-- Start the main loop and server
turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
turbo.ioloop.instance():start()

