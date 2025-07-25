function locals()
    local variables = {}
    local idx = 1
    while true do
        local ln, lv = debug.getlocal(2, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

function upvalues()
    local variables = {}
    local idx = 1
    local func = debug.getinfo(2, "f").func
    while true do
        local ln, lv = debug.getupvalue(func, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end
