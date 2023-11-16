
--[[

** General-purpose environment/debugging methods

]]


function table_print (tt, indent, done)
    done = done or {}
    indent = indent or 0
    print ("Table Print:")
    if type(tt) == "table" then
        local sb = {}
        for key, value in pairs (tt) do
            table.insert(sb, string.rep (" ", indent)) -- indent it
            if type (value) == "table" and not done [value] then
                done [value] = true
                table.insert(sb, "{\n");
                table.insert(sb, table_print (value, indent + 2, done))
                table.insert(sb, string.rep (" ", indent)) -- indent it
                table.insert(sb, "}\n");
            elseif "number" == type(key) then
                table.insert(sb, string.format("\"%s\"\n", tostring(value)))
            else
                table.insert(sb, string.format(
                    "%s = \"%s\"\n", tostring (key), tostring(value)))
            end
        end
        return table.concat(sb)
    else
        return tt .. "\n"
    end
end

function table.val_to_str ( v )
    if "string" == type( v ) then
        v = string.gsub( v, "\n", "\\n" )
        if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
            return "'" .. v .. "'"
        end
        return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
    else
        return "table" == type( v ) and table.tostring( v ) or
            tostring( v )
    end
end

function table.key_to_str ( k )
    if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
        return k
    else
        return "[" .. table.val_to_str( k ) .. "]"
    end
end



function to_string( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return table_Logger.debug(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end
--Logger.debug(to_string {"Lua", user="Mariacher", {{co=coroutine.create(function() end),{number=12345.6789}}, func=function() end}, boolt=true} )


--[[
Author: Julio Manuel Fernandez-Diaz
Date:   January 12, 2007
(For Lua 5.1)

Modified slightly by RiciLake to avoid the unnecessary table traversal in tablecount()

Formats tables with cycles recursively to any depth.
The output is returned as a string.
References to other tables are shown as values.
Self references are indicated.

The string returned is "Lua code", which can be procesed
(in the case in which indent is composed by spaces or "--").
Userdata and function keys and values are shown as strings,
which logically are exactly not equivalent to the original code.

This routine can serve for pretty formating tables with
proper indentations, apart from printing them:

Logger.debug(table.show(t, "t"))   -- a typical use

Heavily based on "Saving tables with cycles", PIL2, p. 113.

Arguments:
t is the table.
name is the name of the table (optional)
indent is a first indentation (optional).
--]]
function table.show(t, name, indent)
    local cart     -- a container
    local autoref  -- for self references

    --[[ counts the number of elements in a table
    local function tablecount(t)
    local n = 0
    for _, _ in pairs(t) do n = n+1 end
    return n
    end
    ]]
    -- (RiciLake) returns true if the table is empty
    local function isemptytable(t) return next(t) == nil end

    local function basicSerialize (o)
        local so = tostring(o)
        if type(o) == "function" then
            local info = debug.getinfo(o, "S")
            -- info.name is nil because o is not a calling level
            if info.what == "C" then
                return string.format("%q", so .. ", C function")
            else
                -- the information is defined through lines
                return string.format("%q", so .. ", defined in (" ..
                    info.linedefined .. "-" .. info.lastlinedefined ..
                    ")" .. info.source)
            end
        elseif type(o) == "number" or type(o) == "boolean" then
            return so
        else
            return string.format("%q", so)
        end
    end

    local function addtocart (value, name, indent, saved, field)
        indent = indent or ""
        saved = saved or {}
        field = field or name

        cart = cart .. indent .. field

        if type(value) ~= "table" then
            cart = cart .. " = " .. basicSerialize(value) .. ";\n"
        else
            if saved[value] then
                cart = cart .. " = {}; -- " .. saved[value]
                    .. " (self reference)\n"
                autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
            else
                saved[value] = name
                --if tablecount(value) == 0 then
                if isemptytable(value) then
                    cart = cart .. " = {};\n"
                else
                    cart = cart .. " = {\n"
                    for k, v in pairs(value) do
                        k = basicSerialize(k)
                        local fname = string.format("%s[%s]", name, k)
                        field = string.format("[%s]", k)
                        -- three spaces between levels
                        addtocart(v, fname, indent .. "   ", saved, field)
                    end
                    cart = cart .. indent .. "};\n"
                end
            end
        end
    end

    name = name or "__unnamed__"
    if type(t) ~= "table" then
        return name .. " = " .. basicSerialize(t)
    end
    cart, autoref = "", ""
    addtocart(t, name, indent)
    return cart .. autoref
end


--// CHILL CODE ™ //--
-- table.ordered( [comp] )
--
-- Lua 5.x add-on for the table library.
-- Table using sorted index.  Uses binary table for fast Lookup.
-- http://lua-users.org/wiki/OrderedTable by PhilippeFremy

-- table.ordered( [comp] )
-- Returns an ordered table. Can only take strings as index.
-- fcomp is a comparison function behaves behaves just like
-- fcomp in table.sort( t [, fcomp] ).
function table.ordered(fcomp)
    local newmetatable = {}

    -- sort func
    newmetatable.fcomp = fcomp

    -- sorted subtable
    newmetatable.sorted = {}

    -- behavior on new index
    function newmetatable.__newindex(t, key, value)
        if type(key) == "string" then
            local fcomp = getmetatable(t).fcomp
            local tsorted = getmetatable(t).sorted
            table.binsert(tsorted, key , fcomp)
            rawset(t, key, value)
        end
    end

    -- behaviour on indexing
    function newmetatable.__index(t, key)
        if key == "n" then
            return table.getn( getmetatable(t).sorted )
        end
        local realkey = getmetatable(t).sorted[key]
        if realkey then
            return realkey, rawget(t, realkey)
        end
    end

    local newtable = {}

    -- set metatable
    return setmetatable(newtable, newmetatable)
end

--// table.binsert( table, value [, comp] )
--
-- LUA 5.x add-on for the table library.
-- Does binary insertion of a given value into the table
-- sorted by [,fcomp]. fcomp is a comparison function
-- that behaves like fcomp in in table.sort(table [, fcomp]).
-- This method is faster than doing a regular
-- table.insert(table, value) followed by a table.sort(table [, comp]).
function table.binsert(t, value, fcomp)
    -- Initialise Compare function
    local fcomp = fcomp or function( a, b ) return a < b end

    --  Initialise Numbers
    local iStart, iEnd, iMid, iState =  1, table.getn( t ), 1, 0

    -- Get Insertposition
    while iStart <= iEnd do
        -- calculate middle
        iMid = math.floor( ( iStart + iEnd )/2 )

        -- compare
        if fcomp( value , t[iMid] ) then
            iEnd = iMid - 1
            iState = 0
        else
            iStart = iMid + 1
            iState = 1
        end
    end

    local pos = iMid+iState
    table.insert( t, pos, value )
    return pos
end

-- Iterate in ordered form
-- returns 3 values i, index, value
-- ( i = numerical index, index = tableindex, value = t[index] )
function orderedPairs(t)
    return orderedNext, t
end
function orderedNext(t, i)
    i = i or 0
    i = i + 1
    local index = getmetatable(t).sorted[i]
    if index then
        return i, index, t[index]
    end
end

function env_global_g()
    for k,v in pairs(_G) do
        print("Global key", k, "value", v)
    end
end

function env_locals()
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

function env_upvalues()
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


function dump_environment_details()
    if (Logger ~= nil) then
        local details = {}
        -- details["Time"] = os.date()
        print("debug 1")
        details["UDID"] = MOAIEnvironment.udid or "<undefined>"
        print("debug 2")
        details["App ID"] = MOAIEnvironment.appID or "<undefined>"
        print("debug 3")
        details["App Version"] = MOAIEnvironment.appVersion or "<undefined>"
        print("debug 4")
        details["OS Brand"] = MOAIEnvironment.osBrand or "<undefined>"
        details["OS Version"] = MOAIEnvironment.osVersion or "<undefined>"
        details["Resource Directory"] = MOAIEnvironment.resourceDirectory or "<undefined>"
        details["Screen DPI"] = MOAIEnvironment.screenDpi or "<undefined>"
        details["Horizontal Resolution"] = MOAIEnvironment.horizontalResolution or "<undefined>"
        details["Vertical Resolution"] = MOAIEnvironment.verticalResolution or "<undefined>"
        details["Display Name"] = MOAIEnvironment.appDisplayName or "<undefined>"
        details["Cache Directory"] = MOAIEnvironment.cacheDirectory or "<undefined>"
        details["Carrier ISO Country Code"] = MOAIEnvironment.carrierISOCountryCode or "<undefined>"
        details["Carrier Mobile Country Code"] = MOAIEnvironment.carrierMobileCountryCode or "<undefined>"
        details["Carrier Mobile Network Code"] = MOAIEnvironment.carrierMobileNetworkCode or "<undefined>"
        details["Carrier Name"] = MOAIEnvironment.carrierName or "<undefined>"
        details["Connection Type"] = MOAIEnvironment.connectionType or "<undefined>"
        details["Country Code"] = MOAIEnvironment.countryCode or "<undefined>"
        details["CPU ABI"] = MOAIEnvironment.cpuabi or "<undefined>"
        details["Device Brand"] = MOAIEnvironment.devBrand or "<undefined>"
        details["Device Name"] = MOAIEnvironment.devName or "<undefined>"
        details["Device Manufacturer"] = MOAIEnvironment.devManufacturer or "<undefined>"
        details["Device Mode"] = MOAIEnvironment.devModel or "<undefined>"
        details["Device Platform"] = MOAIEnvironment.devPlatform or "<undefined>"
        details["Device Product"] = MOAIEnvironment.devProduct or "<undefined>"
        details["Document Directory"] = MOAIEnvironment.documentDirectory or "<undefined>"
        -- details["iOS Retina Display"] = MOAIEnvironment.iosRetinaDisplay or "<undefined>"
        details["Language Code"] = MOAIEnvironment.languageCode or "<undefined>"
        print("debug 5")
        Logger.debug(table.show(details, "environment details:"))
        -- Logger.debug(table.show({}, "environment details:"))
    end
end

env_locals()
dump_environment_details()
