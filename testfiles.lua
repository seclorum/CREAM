local function test_fd_limit()
    local files = {}
    local count = 0
    local step = 100 -- Test in batches to avoid sudden crashes
    local temp_file_prefix = "tempfile_" -- Temporary files for testing

    while true do
        local success, err = pcall(function()
            -- Open a batch of files
            for i = 1, step do
                local filename = temp_file_prefix .. count .. "_" .. i .. ".tmp"
                local file = assert(io.open(filename, "w")) -- Open file in write mode
                file:write("test") -- Write minimal data
                table.insert(files, file)
                count = count + 1
                -- Print progress every 100 files
                if count % 100 == 0 then
                    print("Opened ~" .. count .. " file descriptors")
                end
            end
            collectgarbage("collect") -- Force GC to clean up Lua objects
        end)

        if not success then
            print("Failed to open file descriptors at ~" .. count .. " descriptors")
            print("Error: " .. tostring(err))
            -- Clean up: Close all open files
            for _, file in ipairs(files) do
                pcall(function() file:close() end)
            end
            -- Delete temporary files
            for i = 1, count do
                local filename = temp_file_prefix .. (i - 1) .. "_" .. (i % step + 1) .. ".tmp"
                pcall(function() os.remove(filename) end)
            end
            break
        end
    end

    -- Clean up remaining files
    for _, file in ipairs(files) do
        pcall(function() file:close() end)
    end
    for i = 1, count do
        local filename = temp_file_prefix .. (i - 1) .. "_" .. (i % step + 1) .. ".tmp"
        pcall(function() os.remove(filename) end)
    end

    return count
end

-- Run the test
print("Testing maximum number of file descriptors...")
local max_fds = test_fd_limit()
print("Maximum file descriptors opened: " .. max_fds)
