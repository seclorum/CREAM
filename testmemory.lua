local ffi = require("ffi")
local function test_memory()
    local total = 0
    local chunks = {}
    local step = 1024 * 1024 -- 1 MB chunks
    local max_mb = 0

    while true do
        local success, err = pcall(function()
            -- Allocate memory via FFI to bypass Lua's GC
            local ptr = ffi.new("char[?]", step)
            table.insert(chunks, ptr)
            total = total + step
            max_mb = total / (1024 * 1024)
            collectgarbage() -- Force GC to clean up if needed
        end)
        if not success then
            print("Memory allocation failed at ~" .. math.floor(max_mb) .. " MB")
            break
        end
        -- Optional: Print progress
        if max_mb % 100 == 0 then
            print("Allocated ~" .. math.floor(max_mb) .. " MB")
        end
    end
    return max_mb
end

test_memory()
