-- provide a safety mechanism for enumerations on tables

--- check list for value
-- returns true on discovery
-- @param list table to be inspected
-- @param value thing we are looking for
table.includes = function(list, value)
    for i,x in ipairs(list) do
        if (x == value) then
            return(true)
        end
    end
    return(false)
end

--- check table for key
-- checks if table has key, uses pairs,so useable this function should be used if the table has holes or string keys
-- @param source input table
-- @param key the key we are looking for
-- @return true on match, false otherwise
table.has_key = function( source, key )
    for k, v in pairs( source ) do
        if( k == key ) then
            return true
        end
    end
    return false
end


--- look for a value yourself
-- provided a function, traverses the list
-- until discovery
-- @param list table to be inspected
-- @param func yourself a func
table.detect = function(list, func)
    for i,x in ipairs(list) do
        if (func(x, i)) then
            return(x)
        end
    end
    return(nil)
end

--- see if we don't have it
-- check the list item
-- @param list table to be inspected
-- @param item item of relevance
table.without = function(list, item)
    return table.reject(list, function (x)
        return x == item
    end)
end

--- get all packed entries, until gap
-- func on the provided list
-- @param list table to be inspected
-- @param func do func what you func want
table.each = function(list, func)
    for i,v in ipairs(list) do
        func(v, i)
    end
end

--- get all entries, packed or not, until completion
-- func on the provided list, completely
-- @param list table to be inspected
-- @param func do func what you func want
table.all = function(list, func)
    if (list ~= nil) then
        for i,v in pairs(list) do
            func(v, i)
        end
    end
end

--- get yourself an entry
-- provided a list, erect a selection
-- @param list table to be inspected
-- @param func do func true when entry do
table.select = function(list, func)
    local results = {}
    for i,x in ipairs(list) do
        if (func(x, i)) then
            table.insert(results, x)
        end
    end
    return(results)
end

--- collect the rejects
-- provided a list, func the losers
-- @param list table to be inspected
-- @param func do func the dirty work
table.reject = function(list, func)
    local results = {}
    for i,x in ipairs(list) do
        if (func(x, i) == false) then
            table.insert(results, x)
        end
    end
    return(results)
end

--- split the proceeds
-- provided a list, split until completion
-- @param list table to be inspected
-- @param func make func the splitter
-- @param returns two lists split
table.partition = function(list, func)
    local matches = {}
    local rejects = {}

    for i,x in ipairs(list) do
        if (func(x, i)) then
            table.insert(matches, x)
        else
            table.insert(rejects, x)
        end
    end

    return matches, rejects
end

--- bring it all together
-- pass the lefty to the right-hand side
-- and let return the whole
-- @param source the left-hand-side
-- @param destination the right-hand-side
-- @param returns the whole lot
table.merge = function(source, destination)
    for k,v in pairs(destination) do source[k] = v end
    return source
end

--- believe it or not, lua doesn't give a bit
-- so we have our own funny ways of keeping 'em
-- @param list how much you
table.unshift = function(list, val)
    table.insert(list, 1, val)
end

table.shift = function(list)
    return table.remove(list, 1)
end

table.pop = function(list)
    return table.remove(list)
end

table.push = function(list, item)
    return table.insert(list, item)
end

table.collect = function(source, func)
    local result = {}
    for i,v in ipairs(source) do table.insert(result, func(v)) end
    return result
end

table.empty = function(source)
    return source == nil or next(source) == nil
end

table.present = function(source)
    return not(table.empty(source))
end

table.random = function(source)
    return source[math.random(1, #source)]
end

table.times = function(limit, func)
    for i = 1, limit do
        func(i)
    end
end

table.reverse = function(source)
    local result = {}
    for i,v in ipairs(source) do table.unshift(result, v) end
    return result
end

table.dup = function(source)
    local result = {}
    for k,v in pairs(source) do result[k] = v end
    return result
end

-- fisher-yates shuffle
function table.shuffle(t)
    local n = #t
    while n > 2 do
        local k = math.random(n)
        t[n], t[k] = t[k], t[n]
        n = n - 1
    end
    return t
end

table.keys = function(source)
    local result = {}
    for k,v in pairs(source) do
        table.push(result, k)
    end
    return result
end

table.keyvals = function (source)
    local keyvals = {}
    local x = 0
    for k in pairs(source) do
        x = x + 1
        keyvals[x] = k
    end
    return keyvals
end

table.size = function( source )
    local i = 0
    for _ in pairs( source) do
        i = i + 1
    end
    return i
end


