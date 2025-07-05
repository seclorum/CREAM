local ffi = require("ffi")
ffi.cdef[[
    int socket(int domain, int type, int protocol);
    int close(int fd);
]]
local function test_socket_fd_limit()
    local sockets = {}
    local count = 0
    local step = 100
    while true do
        local success, err = pcall(function()
            for i = 1, step do
                local fd = ffi.C.socket(2, 1, 0) -- AF_INET, SOCK_STREAM
                if fd == -1 then error("Socket creation failed") end
                table.insert(sockets, fd)
                count = count + 1
                if count % 100 == 0 then
                    print("Opened ~" .. count .. " socket file descriptors")
                end
            end
            collectgarbage("collect")
        end)
        if not success then
            print("Failed at ~" .. count .. " socket file descriptors")
            print("Error: " .. tostring(err))
            for _, fd in ipairs(sockets) do
                pcall(function() ffi.C.close(fd) end)
            end
            break
        end
    end
    for _, fd in ipairs(sockets) do
        pcall(function() ffi.C.close(fd) end)
    end
    return count
end
print("Testing maximum socket file descriptors...")
local max_fds = test_socket_fd_limit()
print("Maximum socket file descriptors opened: " .. max_fds)
