local function test_coroutine_limit()
    local coroutines = {}
    local count = 0
    local max_count = 0
    local step = 100 -- Test in batches to avoid sudden crashes

    -- Simple coroutine function
    local function worker()
        -- Minimal work to avoid heavy memory usage
        coroutine.yield()
    end

    while true do
        local success, err = pcall(function()
            -- Create a batch of coroutines
            for i = 1, step do
                local co = coroutine.create(worker)
                table.insert(coroutines, co)
                coroutine.resume(co) -- Start coroutine
                count = count + 1
            end
            -- Force garbage collection to free memory
            collectgarbage("collect")
            -- Print progress every 1000 coroutines
            if count % 1000 == 0 then
                print("Created ~" .. count .. " coroutines")
            end
        end)

        if not success then
            print("Failed to create coroutines at ~" .. count .. " coroutines")
            print("Error: " .. tostring(err))
            break
        end

        max_count = count
    end

    return max_count
end

-- Run the test
print("Testing maximum number of coroutines...")
local max_coroutines = test_coroutine_limit()
print("Maximum coroutines created: " .. max_coroutines)
