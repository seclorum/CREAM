-- LuaJIT Stress Test Script
-- Tests memory usage, file descriptors, coroutines, and table sizes
-- WARNING: This script may crash your system or LuaJIT process. Use with caution!

local function print_status(msg)
    print(string.format("[STATUS] %s", msg))
    collectgarbage("collect") -- Force garbage collection to get accurate memory usage
    print(string.format("Memory used: %d KB", collectgarbage("count")))
end

-- 1. Memory Consumption Test
local function test_memory()
    print_status("Starting memory consumption test...")
    local tables = {}
    local i = 1
    local success = true

    while success do
        local status, err = pcall(function()
            -- Create large table with unique keys
            local t = {}
            for j = 1, 100000 do
                t["key" .. i .. "_" .. j] = string.rep("x", 1000) -- 1KB strings
            end
            tables[i] = t
            i = i + 1
        end)
        if not status then
            print_status(string.format("Memory test stopped: %s", err))
            success = false
        end
        if i % 10 == 0 then
            print_status(string.format("Created %d large tables", i - 1))
        end
    end
    print_status(string.format("Total tables created: %d", i - 1))
    return tables -- Keep tables in scope to hold memory
end

-- 2. File Descriptor Test
local function test_file_descriptors()
    print_status("Starting file descriptor test...")
    local files = {}
    local i = 1
    local success = true

    while success do
        local status, file = pcall(function()
            return io.open("/tmp/testfile_" .. i .. ".txt", "w")
        end)
        if status and file then
            files[i] = file
            i = i + 1
        else
            print_status(string.format("File descriptor test stopped: %s", file or "unknown error"))
            success = false
        end
        if i % 100 == 0 then
            print_status(string.format("Opened %d files", i - 1))
        end
    end
    print_status(string.format("Total file descriptors opened: %d", i - 1))
    return files -- Keep files open to hold descriptors
end

-- 3. Coroutine Test
local function test_coroutines()
    print_status("Starting coroutine test...")
    local coroutines = {}
    local i = 1
    local success = true

    local function coroutine_body()
        while true do
            coroutine.yield()
        end
    end

    while success do
        local status, co = pcall(function()
            return coroutine.create(coroutine_body)
        end)
        if status and co then
            coroutines[i] = co
            coroutine.resume(co) -- Start the coroutine
            i = i + 1
        else
            print_status(string.format("Coroutine test stopped: %s", co or "unknown error"))
            success = false
        end
        if i % 1000 == 0 then
            print_status(string.format("Created %d coroutines", i - 1))
        end
    end
    print_status(string.format("Total coroutines created: %d", i - 1))
    return coroutines
end

-- 4. Table Size Test (Hash and Array Parts)
local function test_table_size()
    print_status("Starting table size test...")
    local t = {}
    local i = 1
    local success = true

    while success do
        local status, err = pcall(function()
            -- Fill both array and hash parts
            t[i] = string.rep("x", 1000) -- Array part
            t["key" .. i] = string.rep("y", 1000) -- Hash part
            i = i + 1
        end)
        if not status then
            print_status(string.format("Table size test stopped: %s", err))
            success = false
        end
        if i % 100000 == 0 then
            print_status(string.format("Table entries: %d", i - 1))
        end
    end
    print_status(string.format("Total table entries: %d", i - 1))
    return t
end

-- Main Test Runner
local function run_tests()
    print("=== Starting LuaJIT Stress Test ===")
    print("WARNING: This may consume significant system resources!")

    -- Run each test and keep results to prevent garbage collection
    local results = {}

    results.memory = test_memory()
    print_status("Memory test completed")

    results.files = test_file_descriptors()
    print_status("File descriptor test completed")

    results.coroutines = test_coroutines()
    print_status("Coroutine test completed")

    results.table = test_table_size()
    print_status("Table size test completed")

    print("=== Stress Test Completed ===")
    print("Results are retained to keep resources allocated. Press Ctrl+C to exit or clear manually.")
    return results
end

-- Execute tests
local results = run_tests()

-- Keep the script running to observe resource usage
while true do
    print_status("Keeping resources allocated...")
    os.execute("sleep 10") -- Sleep to reduce CPU usage
end
