-- Import required modules
local config = require("config") -- Application configuration settings
local turbo = require("turbo") -- TurboLua web framework
local turbo_thread = require("turbo.thread") -- Threading support
local io = require("io") -- Standard I/O library
local posix = require("posix") -- POSIX system calls
local syslog = require("posix.syslog") -- System logging
local cjson = require("cjson") -- JSON encoding/decoding
local syscall = require("syscall") -- System call utilities
local socket = require("socket") -- Port availability checking

-- Global state variables
local state = {
    isExecuting = false, -- Tracks if recording is in progress
    isPlaying = false, -- Tracks if audio playback is active
    isSynchronizing = false -- Tracks if synchronization is active
}

-- Logging utility function
local function cLOG(level, ...)
    local message = table.concat({...}, " ") -- Concatenate arguments into a single message
    syslog.syslog(level, message) -- Log to syslog
    print(string.format("LOG:%d %s", level, message)) -- Log to console for debugging
end

-- Set sync partner based on hostname
local function setSyncPartner()
    local hostname = syscall.gethostname()
    if hostname == "mix-o" then
        config.CREAM_SYNC_PARTNER = "mix-j"
    elseif hostname == "mix-j" then
        config.CREAM_SYNC_PARTNER = "mix-o"
    else
        config.CREAM_SYNC_PARTNER = nil
        cLOG(syslog.LOG_WARNING, "Unknown hostname, sync not supported: " .. hostname)
    end
end
setSyncPartner()

-- Disable stdout buffering for immediate output
io.stdout:setvbuf("no")

-- Load CREAM module for audio handling
local CREAM = require("cream")

-- Initialize command stack
local cSTACK = turbo.structs.deque:new()

-- Check if a port is in use
local function isPortInUse(port)
    local sock, err = socket.bind("0.0.0.0", port)
    if sock then
        sock:close()
        return false
    end
    cLOG(syslog.LOG_DEBUG, "Port check error: " .. tostring(err))
    return true
end

-- Mustache template for the status page
local statusTemplate = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CREAM::{{hostname}}</title>
   <style>
        body { font-family: 'Courier New', monospace; background-color: {{backgroundColor}}; color: white; }
        h1, h2, h3, h4, h5, h6 { color: #999999; }
        a:link, a:visited { color: black; }
        #json-container { font-family: 'Courier New', monospace; white-space: pre-wrap; background-color: #f9f9f9; display: none; padding: 0 18px; border: 1px solid #ddd; }
        .collapsible { cursor: pointer; padding: 18px; border: 1px solid #ddd; margin-bottom: 16px; }
        .string { color: black; } .number { color: orange; } .key { color: blue; font-weight: bold; }
        .boolean { color: brown; } .null { color: white; } .link { color: blue; text-decoration: underline; cursor: pointer; }
        .highlight { background-color: orange; }
        .control-surface { display: flex; }
        .interface-button {
            width: 150px; padding: 10px 20px; margin: 10px; font-size: 16px; text-align: center;
            text-transform: uppercase; cursor: pointer; border: 2px solid #fff; border-radius: 5px;
            background-color: #444; color: #fff; transition: background-color 0.3s, border-color 0.3s, color 0.666s;
        }
        .interface-button:hover { background-color: #fff; color: #333; }
        .start { background-color: #A7F9AB; border-color: #4CAF50; }
        .stop { background-color: #FBB1AB; border-color: #f44336; }
        .empty { background-color: #F9D4B4; border-color: white; }
        .synchronize { background-color: #CBB1FE; border-color: green; }
        .synchronizing { background-color: green; border-color: #CBB1FE; }
        .waveform-container { width: 100%; height: 100px; margin: 10px 0; background-color: #222; border: 1px solid #444; }
        .waveform-controls { margin-top: 5px; display: flex; flex-wrap: wrap; gap: 5px; align-items: center; }
        .waveform-button { padding: 5px 10px; background-color: #555; color: white; border: none; border-radius: 3px; cursor: pointer; }
        .waveform-button:hover { background-color: #777; }
        .waveform-button.active { background-color: #4CAF50; }
        .silence-params { display: flex; gap: 5px; align-items: center; }
        .silence-params input { width: 60px; padding: 2px; font-size: 12px; }
        .region-label { font-size: 12px; color: #ccc; margin-left: 10px; }
        .ws-region { background: rgba(0, 255, 0, 0.3); }
        .ws-minimap { margin-top: 5px; background-color: #333; border: 1px solid #444; }
        .ws-spectrogram { margin-top: 10px; }
        .ws-timeline { margin-top: 5px; }
        .ws-hover { background: rgba(255, 255, 255, 0.2); }
        .error-message { color: red; font-size: 12px; margin-left: 10px; }
    </style>
</head>
<body>
    <!-- WaveSurfer.js and plugins -->
 <script src="/wavesurfer.min.js" onerror="console.error('Failed to load wavesurfer.min.js'); logPluginStatus('wavesurfer')"></script>
    <script src="/regions.min.js" onerror="console.error('Failed to load regions.min.js'); logPluginStatus('regions')"></script>
    <script src="/envelope.min.js" onerror="console.error('Failed to load envelope.min.js'); logPluginStatus('envelope')"></script>
    <script src="/hover.min.js" onerror="console.error('Failed to load hover.min.js'); logPluginStatus('hover')"></script>
    <script src="/minimap.min.js" onerror="console.error('Failed to load minimap.min.js'); logPluginStatus('minimap')"></script>
    <script src="/spectrogram.min.js" onerror="console.error('Failed to load spectrogram.min.js'); logPluginStatus('spectrogram')"></script>
    <script src="/timeline.min.js" onerror="console.error('Failed to load timeline.min.js'); logPluginStatus('timeline')"></script>
    <script src="/zoom.min.js" onerror="console.error('Failed to load zoom.min.js'); logPluginStatus('zoom')"></script>
<script>

    console.log('WaveSurfer after scripts load:', {
        type: typeof WaveSurfer,
        WaveSurfer: WaveSurfer,
        regions: !!WaveSurfer?.Regions,
        envelope: !!WaveSurfer?.Envelope,
        hover: !!WaveSurfer?.Hover,
        minimap: !!WaveSurfer?.Minimap,
        spectrogram: !!WaveSurfer?.Spectrogram,
        timeline: !!WaveSurfer?.Timeline,
        zoom: !!WaveSurfer?.Zoom
    });

        // Wait for WaveSurfer plugins to load
        function waitForPlugins(callback) {
            const plugins = ['Regions', 'Envelope', 'Hover', 'Minimap', 'Spectrogram', 'Timeline', 'Zoom'];
            let attempts = 0;
            function checkPlugin() {
                if (typeof WaveSurfer !== 'undefined' && plugins.every(p => WaveSurfer[p])) {
                    console.log('All plugins loaded:', Object.keys(WaveSurfer));
                    callback();
                } else if (attempts < 5) {
                    attempts++;
                    setTimeout(checkPlugin, 100);
                } else {
                    console.error('Plugin loading timeout:', {
                        regions: !!WaveSurfer.Regions, 
						envelope: !!WaveSurfer.Envelope, 
						hover: !!WaveSurfer.Hover,
                        minimap: !!WaveSurfer.Minimap, 
						spectrogram: !!WaveSurfer.Spectrogram, 
						timeline: !!WaveSurfer.Rimeline, 
						zoom: !!WaveSurfer.zoom
                    });
                    document.getElementById('current-status').innerHTML += '<p class="error-message">Error: Some plugins failed to load.</p>';
                    callback();
                }
            }
            checkPlugin();
        }

        // Toggle JSON debug container
        function toggleContent() {
            var content = document.getElementById("json-container");
            content.style.display = content.style.display === 'none' ? 'block' : 'none';
        }

        // Generate background color from hostname
        function generateBackgroundColor(str) {
            let hashCode = 0;
            for (let i = 0; i < str.length; i++) hashCode = str.charCodeAt(i) + ((hashCode << 5) - hashCode);
            const r = (hashCode & 0xFF0000) >> 16;
            const g = (hashCode & 0x00FF00) >> 8;
            const b = hashCode & 0x0000FF;
            return `rgb(${r},${g},${b})`;
        }

        var jsonObject = {{{jsonData}}};

        // Render JSON with syntax highlighting
        function prettifyAndRenderJSON(jsonObj, containerId) {
            var container = document.getElementById(containerId);
            var jsonString = JSON.stringify(jsonObj, null, 2).replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
            var prettyJson = jsonString.replace(
                /("(\\u[a-f0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g,
                match => {
                    var cls = /^"/.test(match) ? (/:$/.test(match) ? 'key' : 'string') :
                              /true|false/.test(match) ? 'boolean' :
                              /null/.test(match) ? 'null' : 'number';
                    return '<span class="' + cls + '">' + match + '</span>';
                }
            );
            prettyJson = prettyJson.replace(/"Tracks": \[\s*((?:"[^"]*",?\s*)+)\]/g, (match, p1) => {
                var links = p1.replace(/"([^"]*)"/g, '<span class="link" onclick="openLink(\'$1\')">$1</span>');
                return '"Tracks": [' + links + ']';
            });
            container.innerHTML = '<pre>' + prettyJson + '</pre>';
        }

        // Detect silence in audio buffer
        function detectSilence(audioBuffer, sampleRate, threshold, minSilenceDuration) {
            const samples = audioBuffer.getChannelData(0);
            const minSamples = minSilenceDuration * sampleRate;
            const regions = [];
            let silenceStart = null;
            const thresholdAmplitude = Math.pow(10, threshold / 20);
            for (let i = 0; i < samples.length; i++) {
                const amplitude = Math.abs(samples[i]);
                if (amplitude < thresholdAmplitude) {
                    if (silenceStart === null) silenceStart = i;
                } else {
                    if (silenceStart !== null && (i - silenceStart) >= minSamples) {
                        regions.push({ start: silenceStart / sampleRate, end: i / sampleRate });
                    }
                    silenceStart = null;
                }
            }
            if (silenceStart !== null && (samples.length - silenceStart) >= minSamples) {
                regions.push({ start: silenceStart / sampleRate, end: samples.length / sampleRate });
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
    tracks.forEach((track, i) => {
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

    // Create container divs for spectrogram and timeline before initializing WaveSurfer
    waveformData.forEach(data => {
        var waveformContainer = document.getElementById(data.waveformId);
        var spectrogramDiv = document.createElement('div');
        spectrogramDiv.id = data.waveformId + '-spectrogram';
        spectrogramDiv.className = 'ws-spectrogram';
        waveformContainer.parentNode.insertBefore(spectrogramDiv, waveformContainer.nextSibling);
        var timelineDiv = document.createElement('div');
        timelineDiv.id = data.waveformId + '-timeline';
        timelineDiv.className = 'ws-timeline';
        waveformContainer.parentNode.insertBefore(timelineDiv, spectrogramDiv.nextSibling);
    });

    window.wavesurfers = window.wavesurfers || [];
    waveformData.forEach(data => {
        try {
            if (typeof WaveSurfer === 'undefined') throw new Error('WaveSurfer.js failed to load');
            console.log('Initializing WaveSurfer for track:', data.track);
            console.log('Available plugins:', {
                regions: !!WaveSurfer.Regions,
                envelope: !!WaveSurfer.Envelope,
                hover: !!WaveSurfer.Hover,
                minimap: !!WaveSurfer.Minimap,
                spectrogram: !!WaveSurfer.Spectrogram,
                timeline: !!WaveSurfer.Timeline,
                zoom: !!WaveSurfer.Zoom
            });

            var wavesurfer = WaveSurfer.create({
                container: '#' + data.waveformId,
                waveColor: 'violet',
                progressColor: 'purple',
                height: 100,
                responsive: true,
                backend: 'MediaElement',
                plugins: [
                    WaveSurfer.Regions?.create(),
                    WaveSurfer.Envelope?.create({ volume: 1.0, fadeInStart: 0, fadeInEnd: 0, fadeOutStart: 0, fadeOutEnd: 0 }),
                    WaveSurfer.Hover?.create({ lineColor: '#fff', lineWidth: 2, labelBackground: '#555', labelColor: '#fff' }),
                    WaveSurfer.Minimap?.create({ height: 30, waveColor: '#ddd', progressColor: '#999' }),
                    WaveSurfer.Spectrogram?.create({ container: '#' + data.waveformId + '-spectrogram', fftSamples: 512, labels: true }),
                    WaveSurfer.Timeline?.create({ container: '#' + data.waveformId + '-timeline' }),
                    WaveSurfer.Zoom?.create({ zoom: 100 })
                ].filter(plugin => plugin)
            });

            console.log('WaveSurfer plugins initialized:', wavesurfer.plugins);

            wavesurfer.load('/' + data.track);
            wavesurfer.on('ready', () => {
                window.wavesurfers[data.index] = wavesurfer;
                wavesurfer.isSilenceDetected = true;
                wavesurfer.isMinimapVisible = true;
                wavesurfer.isSpectrogramVisible = true;
                wavesurfer.isTimelineVisible = true;
                wavesurfer.isEnvelopeApplied = true;
                // Optionally hide spectrogram and timeline by default
                // if (wavesurfer.spectrogram) wavesurfer.spectrogram.hide();
                // if (wavesurfer.timeline) wavesurfer.timeline.hide();
            });
            if (wavesurfer.regions) {
                wavesurfer.on('region-click', region => wavesurfer.play(region.start, region.end));
                wavesurfer.on('region-created', () => updateRegionLabel(data.index, Object.keys(wavesurfer.regions.list).length));
            }
            wavesurfer.on('error', e => {
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


        // Toggle silence detection
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
                    document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`)?.classList.remove('active');
                    updateRegionLabel(index, 0);
                } else {
                    wavesurfer.getDecodedData().then(audioBuffer => {
                        const regions = detectSilence(audioBuffer, audioBuffer.sampleRate, threshold, duration);
                        regions.forEach((region, idx) => {
                            wavesurfer.regions.add({
                                start: region.start, end: region.end, color: 'rgba(0, 255, 0, 0.3)',
                                data: { type: 'silence', index: idx }, drag: false, resize: false
                            });
                        });
                        wavesurfer.isSilenceDetected = true;
                        document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`)?.classList.add('active');
                        updateRegionLabel(index, regions.length);
                    }).catch(e => {
                        console.error('Silence detection failed for waveform ' + index + ':', e);
                        document.getElementById('error-' + index).textContent = 'Silence detection failed: ' + e.message;
                    });
                }
            } else {
                document.getElementById('error-' + index).textContent = 'Silence detection unavailable: Regions plugin not loaded';
            }
        }

        // Clear regions
        function clearRegions(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.regions) {
                wavesurfer.regions.clear();
                wavesurfer.isSilenceDetected = false;
                document.querySelector(`#waveform-${index} ~ .waveform-controls .silence-toggle`)?.classList.remove('active');
                updateRegionLabel(index, 0);
            }
        }

        // Toggle envelope
        function toggleEnvelope(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.envelope) {
                wavesurfer.isEnvelopeApplied = !wavesurfer.isEnvelopeApplied;
                wavesurfer.envelope.setFade(wavesurfer.isEnvelopeApplied ? 2 : 0, 0, wavesurfer.isEnvelopeApplied ? 2 : 0, 0);
                document.querySelector(`#waveform-${index} ~ .waveform-controls .envelope-toggle`)?.classList.toggle('active', wavesurfer.isEnvelopeApplied);
            } else {
                document.getElementById('error-' + index).textContent = 'Envelope unavailable: Envelope plugin not loaded';
            }
        }

        // Toggle minimap
        function toggleMinimap(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.minimap) {
                wavesurfer.isMinimapVisible = !wavesurfer.isMinimapVisible;
                wavesurfer.isMinimapVisible ? wavesurfer.minimap.show() : wavesurfer.minimap.hide();
                document.querySelector(`#waveform-${index} ~ .waveform-controls .minimap-toggle`)?.classList.toggle('active', wavesurfer.isMinimapVisible);
            } else {
                document.getElementById('error-' + index).textContent = 'Minimap unavailable: Minimap plugin not loaded';
            }
        }

        // Toggle spectrogram
        function toggleSpectrogram(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.spectrogram) {
                wavesurfer.isSpectrogramVisible = !wavesurfer.isSpectrogramVisible;
                wavesurfer.isSpectrogramVisible ? wavesurfer.spectrogram.show() : wavesurfer.spectrogram.hide();
                document.querySelector(`#waveform-${index} ~ .waveform-controls .spectrogram-toggle`)?.classList.toggle('active', wavesurfer.isSpectrogramVisible);
            } else {
                document.getElementById('error-' + index).textContent = 'Spectrogram unavailable: Spectrogram plugin not loaded';
            }
        }

        // Toggle timeline
        function toggleTimeline(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.timeline) {
                wavesurfer.isTimelineVisible = !wavesurfer.isTimelineVisible;
                wavesurfer.isTimelineVisible ? wavesurfer.timeline.show() : wavesurfer.timeline.hide();
                document.querySelector(`#waveform-${index} ~ .waveform-controls .timeline-toggle`)?.classList.toggle('active', wavesurfer.isTimelineVisible);
            } else {
                document.getElementById('error-' + index).textContent = 'Timeline unavailable: Timeline plugin not loaded';
            }
        }

        // Zoom in
        function zoomIn(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.zoom) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() * 2);
            } else {
                document.getElementById('error-' + index).textContent = 'Zoom unavailable: Zoom plugin not loaded';
            }
        }

        // Zoom out
        function zoomOut(index) {
            var wavesurfer = window.wavesurfers[index];
            if (wavesurfer && wavesurfer.zoom) {
                wavesurfer.zoom.zoom(wavesurfer.zoom.getZoom() / 2);
            } else {
                document.getElementById('error-' + index).textContent = 'Zoom unavailable: Zoom plugin not loaded';
            }
        }

        // Update region count label
        function updateRegionLabel(index, count) {
            var label = document.getElementById(`region-label-${index}`);
            if (label) label.textContent = count > 0 ? `${count} silent regions detected` : '';
        }

        // Render control interface
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
            setInterval(() => {
                fetch('/status', { cache: 'no-store' }).then(response => {
                    if (!response.ok) throw new Error('Server responded with status ' + response.status);
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
                }).catch(err => {
                    console.error('Status poll failed:', err);
                    document.getElementById('current-status').innerHTML += '<p class="error-message">Status update failed: ' + err.message + '</p>';
                });
            }, 2000);
        }

        // Render status
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

        // Initialize UI
        document.addEventListener('DOMContentLoaded', () => {
            document.querySelector('.collapsible')?.addEventListener('click', toggleContent);
            waitForPlugins(() => {
                renderStatus(jsonObject, "current-status");
                renderControlInterface(jsonObject, "control-interface");
                prettifyAndRenderJSON(jsonObject, "json-container");
                renderWAVTracks(jsonObject, "wav-tracks");
            });
        });
    </script>
    <div id="current-status"></div>
    <div id="control-interface"></div>
    <div id="wav-tracks"></div>
    <div class="collapsible">::debug::<div id="json-container"></div></div>
</body>
</html>
]]


local function NEWexecuteCommand(command, callback, flag, resetFlag)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo.thread.Thread(function(th)
            cLOG(syslog.LOG_INFO, "Executing command: " .. command)
            local process = io.popen(command .. " 2>&1 ; echo $?", "r")
            local output = {}
            local exitCode
            for line in process:lines() do
                if line:match("^%d+$") then
                    exitCode = tonumber(line)
                else
                    output[#output + 1] = line
                end
                if flag and not flag() then break end
                coroutine.yield()
            end
            process:close()
            output = table.concat(output, "\n")
            if exitCode and exitCode ~= 0 then
                cLOG(syslog.LOG_ERR, "Command failed with exit code " .. exitCode .. ": " .. command .. "\nOutput: " .. output)
            else
                cLOG(syslog.LOG_INFO, "Command execution stopped: " .. command .. "\nOutput: " .. output)
            end
            if resetFlag then
                resetFlag(false)
            end
            if callback then
                callback(output)
            end
            th:stop()
        end)
        thread:wait_for_finish()
    end)
end


-- Utility function to execute shell commands
local function executeCommand(command, callback, flag, resetFlag)
    turbo.ioloop.instance():add_callback(function()
        local thread = turbo_thread.Thread(function(th)
            cLOG(syslog.LOG_INFO, "Executing command: " .. command)
            local process = io.popen(command .. " ; echo $?")
            local output = ""
            local exitCode
            for chunk in process:lines() do
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
                cLOG(syslog.LOG_INFO, "Command completed: " .. command .. "\nOutput: " .. output)
            end
            if resetFlag then resetFlag(false) end
            if callback then callback(output) end
            th:stop()
        end)
        thread:wait_for_finish()
    end)
end

-- JavaScript file handler
local creamJsHandler = class("creamJsHandler", turbo.web.RequestHandler)
function creamJsHandler:get(jsFile)
    pcall(function()
        local jsFilePath = config.CREAM_STATIC_DIRECTORY .. jsFile
        cLOG(syslog.LOG_INFO, "Serving JS file: " .. jsFilePath)
        local file = io.open(jsFilePath, "rb")
        if not file then
            cLOG(syslog.LOG_ERR, "JS file not found: " .. jsFilePath)
            self:set_status(404)
            return self:write("File not found: " .. jsFilePath)
        end
        local content = file:read("*a")
        file:close()
        self:set_header("Content-Type", "application/javascript") -- Use standard MIME type
        self:set_header("Cache-Control", "public, max-age=3600") -- Cache for 1 hour
        self:write(content)
    end, function(err)
        cLOG(syslog.LOG_ERR, "JS handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Status page handler
local creamWebStatusHandler = class("creamWebStatusHandler", turbo.web.RequestHandler)
function creamWebStatusHandler:get()
    pcall(function()
        local hostname = syscall.gethostname()
        local userData = {
            hostname = hostname,
            partner = config.CREAM_SYNC_PARTNER or "none",
            backgroundColor = hostname == "mix-o" and "#8B4000" or hostname == "mix-j" and "#083F71" or "#1b2a3f",
            app = {
                recording = state.isExecuting,
                synchronizing = state.isSynchronizing,
                name = config.APP_NAME,
                version = config.CREAM_APP_VERSION,
                edit = CREAM.edit or { current_recording = "", Tracks = {} },
                io = CREAM.devices and CREAM.devices.online or {}
            }
        }
        pcall(CREAM.update, CREAM, function(err)
            cLOG(syslog.LOG_ERR, "CREAM update failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        end)
        cLOG(syslog.LOG_DEBUG, "Rendering /status with current_recording: " .. tostring(userData.app.edit.current_recording))
        local jsonData = cjson.encode(userData)
        self:write(turbo.web.Mustache.render(statusTemplate, {
            hostname = userData.hostname,
            backgroundColor = userData.backgroundColor,
            jsonData = jsonData,
            app = userData.app,
            partner = userData.partner
        }))
    end, function(err)
        cLOG(syslog.LOG_ERR, "Status handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end
function creamWebStatusHandler:on_finish()
    collectgarbage("collect") -- Clean up memory
end

-- Start recording handler
local creamWebStartHandler = class("creamWebStartHandler", turbo.web.RequestHandler)
function creamWebStartHandler:get()
    pcall(function()
        if state.isExecuting then
            cLOG(syslog.LOG_WARNING, "Recording already in progress: " .. tostring(CREAM.edit and CREAM.edit.current_recording or "none"))
            self:write("Recording already in progress")
            return
        end
        CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
        CREAM.edit.current_recording = string.format("%s_%s.wav",
            syscall.gethostname(),
            os.date('%Y-%m-%d@%H:%M:%S.') .. string.match(tostring(os.clock()), "%d%.(%d+)"))
        local command = string.format(
            "%s -vvv -f cd -t wav %s%s -D plughw:CARD=MiCreator,DEV=0 2>&1 > %sarecord.log",
            config.ARECORD_PATH or "/usr/bin/arecord",
            config.CREAM_ARCHIVE_DIRECTORY, CREAM.edit.current_recording, config.CREAM_ARCHIVE_DIRECTORY)
        executeCommand(command, function(output)
            if output:match("error") then
                state.isExecuting = false
                cLOG(syslog.LOG_ERR, "Recording failed: " .. output)
            else
                state.isExecuting = true
                cLOG(syslog.LOG_INFO, "Started recording: " .. CREAM.edit.current_recording)
            end
        end, function() return state.isExecuting end, function(val) state.isExecuting = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
    end, function(err)
        cLOG(syslog.LOG_ERR, "Start handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Stop recording handler
local creamWebStopHandler = class("creamWebStopHandler", turbo.web.RequestHandler)
function creamWebStopHandler:get()
    pcall(function()
        local command = "killall arecord"
        CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
        cLOG(syslog.LOG_INFO, "Stopping recording: " .. tostring(CREAM.edit.current_recording or "none"))
        CREAM.edit.current_recording = ""
        executeCommand(command, function(result)
            cLOG(syslog.LOG_DEBUG, "Stop command result: " .. result)
            state.isExecuting = false
        end, function() return false end)
        self:set_status(303)
        self:set_header("Location", "/status")
    end, function(err)
        cLOG(syslog.LOG_ERR, "Stop handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Clear recordings handler
local creamWebEmptyHandler = class("creamWebEmptyHandler", turbo.web.RequestHandler)
function creamWebEmptyHandler:get()
    pcall(function()
        local command = string.format("find %s -name '*.wav' -delete", config.CREAM_ARCHIVE_DIRECTORY)
        CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
        cLOG(syslog.LOG_INFO, "Clearing recordings")
        CREAM.edit.current_recording = ""
        state.isExecuting = false
        executeCommand(command, function(result)
            cLOG(syslog.LOG_DEBUG, "Clear command result: " .. result)
        end, function() return false end)
        self:set_status(303)
        self:set_header("Location", "/status")
    end, function(err)
        cLOG(syslog.LOG_ERR, "Empty handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Synchronize recordings handler
local creamWebSynchronizeHandler = class("creamWebSynchronizeHandler", turbo.web.RequestHandler)
function creamWebSynchronizeHandler:get()
    pcall(function()
        if not config.CREAM_SYNC_PARTNER then
            cLOG(syslog.LOG_WARNING, "Synchronization not supported on this host")
            self:write("Synchronization not supported")
            self:set_status(303)
            self:set_header("Location", "/status")
            return
        end
        local command = state.isSynchronizing and "killall rsync" or string.format(
            "rsync -avz --include='*.wav' ibi@%s.local:%s %s 2>&1 > %srsync.log",
            config.CREAM_SYNC_PARTNER, config.CREAM_ARCHIVE_DIRECTORY,
            config.CREAM_ARCHIVE_DIRECTORY, config.CREAM_ARCHIVE_DIRECTORY)
        state.isSynchronizing = not state.isSynchronizing
        cLOG(syslog.LOG_INFO, state.isSynchronizing and "Starting synchronization" or "Stopping synchronization")
        executeCommand(command, nil, function() return state.isSynchronizing end, function(val) state.isSynchronizing = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
    end, function(err)
        cLOG(syslog.LOG_ERR, "Synchronize handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Play audio handler
local creamWebPlayHandler = class("creamWebPlayHandler", turbo.web.RequestHandler)
function creamWebPlayHandler:get(fileToPlay)
    pcall(function()
        local command = string.format("%s %s%s -d 0 2>&1",
            config.APLAY_PATH or "/usr/bin/aplay",
            config.CREAM_ARCHIVE_DIRECTORY, fileToPlay)
        cLOG(syslog.LOG_INFO, "Play filename: " .. fileToPlay)
        cLOG(syslog.LOG_INFO, "      Command: " .. command)
        state.isPlaying = true
        cLOG(syslog.LOG_INFO, "Playing: " .. fileToPlay)
        executeCommand(command, nil, function() return state.isPlaying end, function(val) state.isPlaying = val end)
        self:set_status(303)
        self:set_header("Location", "/status")
    end, function(err)
        cLOG(syslog.LOG_ERR, "Play handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- WAV file handler
local creamWavHandler = class("creamWavHandler", turbo.web.RequestHandler)
function creamWavHandler:get(wavFile)
    pcall(function()
        local wavFilePath = config.CREAM_ARCHIVE_DIRECTORY .. wavFile
        cLOG(syslog.LOG_INFO, "Serving WAV file: " .. wavFilePath)
        local file = io.open(wavFilePath, "rb")
        if not file then
            cLOG(syslog.LOG_ERR, "WAV file not found: " .. wavFilePath)
            self:set_status(404)
            return self:write("File not found")
        end
        local content = file:read("*a")
        file:close()
        self:set_header("Content-Type", "audio/wav")
        self:write(content)
    end, function(err)
        cLOG(syslog.LOG_ERR, "WAV handler error: " .. tostring(err) .. "\nStack: " .. debug.traceback())
        self:set_status(500)
        self:write("Internal server error")
    end)
    self:finish()
end

-- Favicon handler
local creamFaviconHandler = class("creamFaviconHandler", turbo.web.RequestHandler)
function creamFaviconHandler:get()
    self:set_status(204)
    self:finish()
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
    pcall(function()
        CREAM.devices = CREAM.devices or { online = {}, init = function() end, dump = function() end }
        CREAM.devices:init()
        CREAM.devices:dump()
    end, function(err)
        cLOG(syslog.LOG_ERR, "Failed to initialize CREAM devices: " .. tostring(err) .. "\nStack: " .. debug.traceback())
    end)
end)

-- Define web application routes
local creamWebApp = turbo.web.Application:new({
  {"/status", creamWebStatusHandler},
  {"/start", creamWebStartHandler},
  {"/stop", creamWebStopHandler},
  {"/empty", creamWebEmptyHandler},
  {"/synchronize", creamWebSynchronizeHandler},
  {"/(.*%.js)$", creamJsHandler},
--  {"/spectrogram.min.js", creamJsHandler},
  {"/play/(.*)$", creamWebPlayHandler},
  {"/favicon.ico", creamFaviconHandler},
  {"^/.*%.wav$", creamWavHandler},
  {"^/$", turbo.web.StaticFileHandler, "./html/index.html"},
})

-- Initialize CREAM
pcall(function()
    CREAM.edit = CREAM.edit or { current_recording = "", Tracks = {} }
    CREAM:init()
end, function(err)
    cLOG(syslog.LOG_ERR, "CREAM initialization failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
end)

-- Check port availability
if isPortInUse(config.CREAM_APP_SERVER_PORT) then
    cLOG(syslog.LOG_ERR, string.format("Port %d is already in use.", config.CREAM_APP_SERVER_PORT))
    os.exit(1)
end

-- Start server
creamWebApp:listen(config.CREAM_APP_SERVER_PORT)

-- Main loop for processing command stack
local function creamMain()
    while cSTACK:size() > 0 do
        local command = cSTACK:pop()
        if command then
            pcall(command, function(err)
                cLOG(syslog.LOG_ERR, "Command execution failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
            end)
        end
        if state.isExecuting then
            pcall(CREAM.update, CREAM, function(err)
                cLOG(syslog.LOG_ERR, "CREAM update failed: " .. tostring(err) .. "\nStack: " .. debug.traceback())
            end)
        end
    end
    turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
end

-- Start the main loop and server
turbo.ioloop.instance():add_timeout(turbo.util.gettimemonotonic() + config.CREAM_COMMAND_INTERVAL, creamMain)
turbo.ioloop.instance():start()
