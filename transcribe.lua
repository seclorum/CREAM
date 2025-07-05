-- Function to transcribe a .wav file to .txt using pocketsphinx (offline)
-- Compatible with Debian (pocketsphinx_continuous) and macOS (pocketsphinx)
-- @param wav_path: string, path to the input .wav file
-- @return: boolean (success/failure), string (error message or output file path)
function transcribeWavToTxt(wav_path)
    -- Validate input
    if not wav_path or type(wav_path) ~= "string" then
        return false, "Invalid or missing .wav file path"
    end

    -- Check if the .wav file exists
    local f = io.open(wav_path, "r")
    if not f then
        return false, "Wav file does not exist: " .. wav_path
    end
    f:close()

    -- Extract directory and filename
    local dir = wav_path:match("(.*/)") or "./"
    local filename = wav_path:match("([^/]+)%.wav$") or "output"
    local txt_path = dir .. filename .. ".txt"
    local temp_wav = dir .. filename .. "_temp.wav"
    local temp_output = dir .. filename .. "_temp.out"

    -- Detect operating system
    local is_macos = jit.os == "OSX" -- TurboLua (LuaJIT) provides jit.os
    local binary, model_base_path
    if is_macos then
        binary = "pocketsphinx"
        model_base_path = "/opt/homebrew/opt/cmu-pocketsphinx/share/pocketsphinx/model"
    else
        binary = "pocketsphinx_continuous"
        model_base_path = "/usr/share/pocketsphinx/model"
    end

    -- Check if the binary exists
    local check_binary_cmd = is_macos and "command -v " .. binary or "which " .. binary
    local check_binary = os.execute(check_binary_cmd)
    if check_binary ~= 0 then
        -- Fallback to pocketsphinx_continuous on macOS
        if is_macos then
            binary = "pocketsphinx_continuous"
            check_binary_cmd = "command -v " .. binary
            check_binary = os.execute(check_binary_cmd)
            if check_binary ~= 0 then
                return false, "Required binary not found: pocketsphinx or pocketsphinx_continuous"
            end
        else
            return false, "Required binary not found: " .. binary
        end
    end

    -- Preprocess .wav file to ensure 16-bit, 16 kHz, mono
    local sox_command = string.format("sox %q -r 16000 -c 1 -b 16 %q 2>&1", wav_path, temp_wav)
    local sox_handle = io.popen(sox_command, "r")
    local sox_output = sox_handle:read("*a")
    local sox_success, sox_status, sox_exit_code = sox_handle:close()

    -- Check if preprocessing succeeded
    local temp_file = io.open(temp_wav, "r")
    if not sox_success or not temp_file then
        if temp_file then temp_file:close() end
        os.remove(temp_wav)
        return false, string.format("Audio preprocessing failed: %s (exit code: %s)\nsox output: %s",
            sox_status or "unknown", sox_exit_code or "unknown", sox_output or "none")
    end
    temp_file:close()

    -- Construct command based on platform
    local command
    if is_macos then
        -- macOS: Use pocketsphinx with 'single' mode
        command = string.format(
            "%s -hmmdir %s/en-us -lmdir %s/en-us -dict %s/en-us/cmudict-en-us.dict single %q > %q 2> %q",
            binary, model_base_path, model_base_path, model_base_path, temp_wav, txt_path, temp_output
        )
    else
        -- Debian: Use pocketsphinx_continuous
        command = string.format(
            "%s -infile %q -lm %s/en-us/en-us.lm.bin -dict %s/en-us/cmudict-en-us.dict -hmm %s/en-us > %q 2> %q",
            binary, temp_wav, model_base_path, model_base_path, model_base_path, txt_path, temp_output
        )
    end

    -- Execute the command with explicit exit code capture
    local wrapped_command = string.format("%s; echo $?", command)
    local handle = io.popen(wrapped_command, "r")
    local output = handle:read("*a")
    local success, status, exit_code = handle:close()

    -- Extract exit code from output (last line)
    local actual_exit_code = tonumber(output:match("(%d+)$")) or 0

    -- Read temporary output file for errors
    local error_output = ""
    local output_file = io.open(temp_output, "r")
    if output_file then
        error_output = output_file:read("*a")
        output_file:close()
        os.remove(temp_output)
    end

    -- Clean up temporary .wav file
    os.remove(temp_wav)

    -- Check if transcription file is empty or missing
    local txt_file = io.open(txt_path, "r")
    local is_empty = true
    local content = ""
    if txt_file then
        content = txt_file:read("*a")
        txt_file:close()
        is_empty = content == ""
    end

    -- Optionally extract plain text from JSON (for macOS)
    if is_macos and not is_empty then
        local plain_text = content:match('"t":"(.-)"') or content
        local txt_file = io.open(txt_path, "w")
        if txt_file then
            txt_file:write(plain_text)
            txt_file:close()
        end
    end

    if success and actual_exit_code == 0 and not is_empty then
        return true, txt_path
    else
        return false, string.format("Transcription failed: %s (exit code: %s)\nError Output: %s\nTranscription Content: %s",
            status or "unknown", actual_exit_code, error_output or "none", content or "none")
    end
end

--[[
local success, result = transcribeWavToTxt("/Users/jayvaughan/Documents/Development/lab/transcription_hacking/test_audio.wav") -- or "/home/user/audio.wav"
if success then
    print("Transcription saved to: " .. result)
else
    print("Error: " .. result)
end
]]
