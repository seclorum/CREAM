
function deg2num(lon, lat, zoom)
    local n = 2 ^ zoom
    local lon_deg = tonumber(lon)
    local lat_rad = math.rad(lat)
    local xtile = math.floor(n * ((lon_deg + 180) / 360))
    local ytile = math.floor(n * (1 - (math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi)) / 2)
    return xtile, ytile
end

function num2deg(x, y, z)
    local n = 2 ^ z
    local lon_deg = x / n * 360.0 - 180.0
    local lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    local lat_deg = lat_rad * 180.0 / math.pi
    return lon_deg, lat_deg
end

-- -- Returns the pixel value based on the dp-value (base dpi = 160)
-- function dp2px(dp)
--     return dp * (DPI / 160)
-- end

-- function px2dp( px )
--     return px * 160 / DPI
-- end

-- walk up an object tree and get each's positions inside their parent container
function rGetPos( obj, lvl )
    lvl = lvl or 1

    if obj.getPos then
        local x, y = obj:getPos()
        local name
        if obj.name then
            name = obj.name
        elseif obj._name then
            name = obj._name
        elseif obj.id then
            name = tostring(obj.id)
        elseif obj._id then
            name = tostring(obj._id)
        end
        Logger.debug( "rGetPos: lvl:", tostring(lvl), "name :", name, "pos x/y: ", x, y )

        if obj.getParent and obj:getParent() ~= nil then
            rGetPos( obj:getParent(), lvl + 1 )
        end
    end
end

-- walk up an object tree and accumulate the positions to get the absolute pixel coordinates of the given object
function getAbsolutePosition( obj, pos )
    pos = pos or { x = 0, y = 0 }

    if obj.getPos then
        local x, y = obj:getPos()
        pos.x = pos.x + x
        pos.y = pos.y + y

        if obj.getParent and obj:getParent() ~= nil then
            pos = getAbsolutePosition( obj:getParent(), pos )
        end
    end

    return pos
end

function dump_varargs(...)
    local args = {...}
    Logger.debug( table.show(args, "DUMPED VARARGS") )
end

function create_path( path )
    if not MOAIFileSystem.checkPathExists( path ) then
        MOAIFileSystem.affirmPath( path )
    end
end

function create_mapcache_dirs()
    local ms = Defaults.MAP_SOURCES

    for i = 1, ms.depth do
        local src = ms[i]
        local path = Defaults.MAPCACHE_SAVEDIR .. "/" .. ms[src].tilesourcename

        create_path( path )

        for j = Defaults.DEFAULT_ZOOM_MIN, Defaults.DEFAULT_ZOOM_MAX do
            create_path( path .. "/" .. tostring(j) )
        end

    end
end

function clamp( val, min, max )
    if val < min then
        val = min
    elseif val > max then
        val = max
    end
    return val
end

-- search recursively for a key in passed object or object's parent
function rSearchKey( obj, key, lvl )
    lvl = lvl or 1

    if obj[ key ] then
        return obj[ key ]
    else
        if obj.getParent then
            return rSearchKey( obj:getParent(), key, lvl + 1 )
        else
            Logger.warn( "rSearchKey: could not get key '" .. key .. "' - searched ".. tostring(lvl) .. " levels" )
            return nil
        end
    end
end


