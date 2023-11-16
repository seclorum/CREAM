local M = {}




M.spheroid = {}
-- seems to be earth radius [m]?
M.spheroid.a = 6378100  -- axis

local EARTH_RADIUS_m = 6378100

local PI    = 3.141592654
local sin = math.sin
local cos = math.cos
local asin = math.asin
local atan2 = math.atan2
local log   = math.log
local tan   = math.tan
local floor = math.floor
local atan  = math.atan
local exp   = math.exp
local sqrt  = math.sqrt


if false then
    M.PI    = 3.141592654
    M.log   = math.log
    M.tan   = math.tan
    M.cos   = math.cos
    M.sin   = math.sin
    M.floor = math.floor
    M.atan  = math.atan
    M.exp   = math.exp
    M.sqrt  = math.sqrt
    M.NUMSUBTILE      = 8
    M.NUMSUBSAMPLEMGM = 256
    M.NUMSUBSAMPLENED = 32
end

function M.directionVector( p1, p2 )
    local d = {}
    d.lat = p2.lat - p1.lat
    d.lon = p2.lon - p1.lon

    return d
end


function deg2rad( v )
    return v * 2 * math.pi / 360
end

function rad2deg( v )
    return v * 360 / ( 2 * math.pi )
end

function M.zeta( p1, p2 )
    local phi_1    = deg2rad( p1.lat )
    local lambda_1 = deg2rad( p1.lon )
    local phi_2    = deg2rad( p2.lat )
    local lambda_2 = deg2rad( p2.lon )

    local zeta =  math.acos(
        math.sin( phi_1 ) * math.sin( phi_2 )
        + math.cos( phi_1 ) * math.cos( phi_2 ) * math.cos( lambda_2 - lambda_1 )
    )
    return zeta

end

-- distance between 2 points in meters
function M.distance( p1, p2 )
    local zeta = M.zeta( p1, p2 )
    -- z * 2rPI/2PI
    return zeta * EARTH_RADIUS_m
end

--- calculates secans
-- calculates secans of given angle
-- sec(x) = 1 / cos(x)
-- @param x angle [rad]
-- @return secans
function M.sec(x)
    return 1 / cos(x)
end

--- Haversine Function
-- calculates haversine of given angle
-- haversin(x) = sin^2(x/2)
-- @param x angle [rad]
-- @return haversine
function M.haversin(theta)
    local theta2     = theta / 2
    local sin_theta2 = sin( theta2 )

    return sin_theta2 * sin_theta2
end

-- Functions to compute the following
-- * distance between two points (lat1, lon1) and (lat2, lon2)
-- * initial bearing of second point (lat2, lon2) from first point (lat1, lon2)
-- * position of second point (lat2, lon2) a given distance and bearing from first point (lat1, lon1)
--
-- Thanks to http://www.movable-type.co.uk/scripts/latlong.html for the Javascript that these
-- functions were based on.

-- map latitude/longitude and zoom level to tile number (x/y)

-- FIXME misleading function name, input is [deg]?, also in tools.lua
--- calculate tile coords for lat/lon coords at given zoom level
-- calculates tile coordinates for a given point described by latitude, longitude
-- at a given zoom level
-- @param lon longitude
-- @param lat latitude
-- @param zoom zoom level
-- @return xtile, ytile coordinates
function M.deg2num( lon, lat, zoom )
    local n       = 2 ^ zoom
    local lon_deg = tonumber( lon )
    local lat_rad = math.rad( lat )
    local xtile   = math.floor( n * ( ( lon_deg + 180 ) / 360 ) )
    local ytile   = math.floor( n * ( 1 - ( math.log( math.tan( lat_rad ) + ( 1 / math.cos( lat_rad ) ) ) / math.pi ) ) / 2 )
    return xtile, ytile
end

-- FIXME misleading function name, also in tools.lua, output uses wrong units
--- calculates longitude and latitude for tile coordinates at given zoom level
-- @param x x tile coordinate
-- @param y y tile coordinate
-- @param z zoom level
-- @return lon, lat longitude and latitude [deg]
function M.num2deg(x, y, z)
    local n = 2 ^ z
    local lon_deg = x / n * 360.0 - 180.0
    local lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    local lat_deg = lat_rad * 180.0 / math.pi
    return lon_deg, lat_deg
end

-- not called
--- calculate initial bearing
-- calculates initial bearing for lat1, lon1 facing lat2, lon2
-- @param lat1 latitude of origin
-- @param lon1 longitude of origin
-- @param lat2 latitude of target
-- @param lon2 longitude of target
-- @param geoid unused
-- @return bering angle [rad]
function M.bearing( lat1, lon1, lat2, lon2, geoid )
    local dlon    = lon2 - lon1
    local y       = sin( dlon ) * cos( lat2 )
    local x       = cos( lat1 ) * sin( lat2 ) - sin( lat1 ) * cos( lat2 ) * cos( dlon )
    local bearing = atan2( y, x )
    -- normalize result
    return math.fmod( bearing + 2 * math.pi, 2 * math.pi )
end

--- calculate destination coordinates for a point, bearing and distance
-- calculates the destination coordinates for a point described by latitude, longitude, distance and  a given bearing.
-- @param lat1 latitude
-- @param lon1 longitude
-- @param distance [m]
-- @param bearing [rad]
-- @param geoid geoid
-- @return lat2, lon2 coordinates of target
function M.destination( lat1, lon1, distance, bearing, geoid )
    local lat2 = asin(  sin( lat1 ) * cos( distance / geoid.a )
        + cos( lat1 ) * sin( distance / geoid.a ) * cos( bearing ) )
    local lon2 = lon1 + atan2( sin( bearing ) * sin( distance / geoid.a ) * cos( lat1 ),
        cos( distance / geoid.a ) - sin( lat1 ) * sin( lat2 ) )
    return lat2, lon2
end


-- not called
-- Given a set of track points, calculate points at fixed distances along the track.
function M.calculate_d_points(trk, d_interval)
    local tp1 = {}
    local tp2 = {}
    local total_d = 0
    local partial_d = 0
    local rounded_d = 0
    local d_points = {}
    local total_t = 0
    local partial_t = 0

    for i = 1, #trk - 1 do
        tp1 = trk[i]
        tp2 = trk[i+1]

        while rounded_d <= total_d + tp1.distance do
            partial_d = rounded_d - total_d
            partial_t = partial_d / tp1.speed

            local tp3 = {}
            tp3.lat, tp3.lon = geocalcs.destination(tp1.lat, tp1.lon, partial_d, tp1.bearing, geocalcs.spheroid)
            tp3.time = tp1.time + partial_t
            tp3.trktime = total_t + partial_t
            tp3.distance = rounded_d
            tp3.speed = tp1.distance / tp1.duration

            d_points[#d_points+1] = tp3

            rounded_d = rounded_d + d_interval
        end

        total_d = total_d + tp1.distance
        total_t = total_t + tp1.duration
    end

    return d_points
end


-- not called
-- Given a set of track points, calculate a set of points at fixed times along the track.
-- If start time is omitted or zero, then the points are relative to the start of the track.
-- If the start time is calculated from the time of the first trackBy specifying the start
-- time correctly, it is possible to ensure that the times
function M.calculate_t_points(trk, t_interval, start_time)
    local tp1 = {}
    local tp2 = {}
    local total_t = 0
    local partial_t = 0
    local rounded_t = start_time or t_interval - math.fmod(trk[1].time, t_interval)
    local total_d = 0
    local partial_d = 0
    local t_points = {}

    for i = 1, #trk - 1 do
        tp1 = trk[i]
        tp2 = trk[i+1]

        while rounded_t <= total_t + tp1.duration do
            partial_t = rounded_t - total_t
            partial_d = tp1.speed * partial_t

            local tp3 = {}
            tp3.lat, tp3.lon = geocalcs.destination(tp1.lat, tp1.lon, partial_d, tp1.bearing, geocalcs.spheroid)
            tp3.time = tp1.time + partial_t
            tp3.trktime = total_t + partial_t
            tp3.distance = total_d + partial_d
            tp3.speed = tp1.distance / tp1.duration

            t_points[#t_points+1] = tp3

            rounded_t = rounded_t + t_interval
        end

        total_t = total_t + tp1.duration
        total_d = total_d + tp1.distance
    end

    return t_points
end



-- Example to convert latitude/longitude
-- to/from tile/subtile indicies/coords
-- for MGM map filenames
--
-- Based loosely on this description from JCamp...@gmail.com
-- https://groups.google.com/forum/m/?fromgroups#!topic/google-maps-api/oJkyualxzyY
--
-- For a good description of tiles and zoom levels
-- http://www.mapbox.com/developers/guide/
--
-- For a description of the Mercator Projection
-- http://en.m.wikipedia.org/wiki/Mercator_projection
--
-- To convert latitude/longitude/height to x/y/z
-- www.wollindina.com/HP-33S/XYZ_1.pdf



M.NUMSUBTILE      = 8
M.NUMSUBSAMPLEMGM = 256
M.NUMSUBSAMPLENED = 32

--- converts feet to meters
-- converts feet to meters
-- @param feet [ft]
-- @return meters [m]
function M.feet2meters(feet)
    return feet * 1609.344 / 5280.0
end

--- shift left
-- emulates shift by multiplication
-- res = x * 2^by
-- @param x value to be shifted
-- @param by shift by
-- @return right shifted x
function M.lshift(x, by)
    return x * 2 ^ by
end

--- shift right
-- emulates shift right by division
-- res = floor( x / 2^by )
-- @param x value to be shifted
-- @param by shift by
-- @return left shifted x
function M.rshift(x, by)
    return math.floor(x / 2 ^ by)
end

-- TODO [rad] instead of [deg]
--- calculate tile coords for lat/lon coords at given zoom level
-- calculates tile coordinates for a given point described by latitude, longitude
-- at a given zoom level
-- @param latitude latitude [deg]
-- @param longitude longitude [deg]
-- @param zoom zoom level
-- @return xtile, ytile coordinates
function M:getTileNumber( latitude,  longitude, zoom )
    if latitude == nil then return end
    if longitude == nil then return end

    --  Logger.warn("GetTileNumber, lat:", latitude, "long:", longitude, " zoom:", zoom)
    local xtile = ( longitude + 180 ) / 360 * ( M.lshift(1, zoom) )
    local l     = log( tan( latitude * PI / 180 ) + M.sec( latitude * PI / 180 ) )
    local ytile = ( 1 - l / PI ) / 2 * ( M.lshift( 1, zoom ) )

    return math.floor( xtile ), math.floor( ytile )
end

-- FIXME function also available in geocoords.lua
-- only called from test()
function M.coord2tile(zoom, lat, lon)
    local radlat   = lat*(PI/180)
    local radlon   = lon*(PI/180)

    local tile     = { }
    tile.mercx     = radlon
    tile.mercy     = log(tan(radlat) + 1/cos(radlat))
    tile.cartx     = tile.mercx + PI
    tile.carty     = PI - tile.mercy
    tile.worldu    = tile.cartx/(2*PI)
    tile.worldv    = tile.carty/(2*PI)
    tile.x         = tile.worldu*(2^zoom)/M.NUMSUBTILE
    tile.y         = tile.worldv*(2^zoom)/M.NUMSUBTILE
    tile.ix        = floor(tile.x)
    tile.iy        = floor(tile.y)
    tile.subtilex  = M.NUMSUBTILE*(tile.x - tile.ix)
    tile.subtiley  = M.NUMSUBTILE*(tile.y - tile.iy)
    tile.subtileix = floor(tile.subtilex)
    tile.subtileiy = floor(tile.subtiley)
    tile.subtileu  = tile.subtilex - tile.subtileix
    tile.subtilev  = tile.subtiley - tile.subtileiy

    return tile
end

-- FIXME function also available in geocoords.lua
-- only called from test()
function M.tile2coord(zoom, tilex, tiley)
    local coord  = { }
    coord.worldu = M.NUMSUBTILE*tilex/(2^zoom)
    coord.worldv = M.NUMSUBTILE*tiley/(2^zoom)
    coord.cartx  = 2*PI*coord.worldu
    coord.carty  = 2*PI*coord.worldv
    coord.mercx  = coord.cartx - PI
    coord.mercy  = PI - coord.carty

    local radlon = coord.mercx
    local radlat = 2*atan(exp(coord.mercy)) - PI/2

    coord.lat = radlat/(PI/180)
    coord.lon = radlon/(PI/180)

    return coord
end

-- FIXME function also available in geocoords.lua
-- only called from test()
function M.coord2xyz(lat, lon, height)
    -- WSG84/NAD83 coordinate system
    -- meters
    local a      = 6378137.0
    local e2     = 0.006694381
    local radlat = lat*(PI/180)
    local radlon = lon*(PI/180)
    local s2     = sin(radlat)*sin(radlat)
    local v      = a/sqrt(1.0 - e2*s2)

    local xyz = { }
    xyz.x     = (v + height)*cos(radlat)*cos(radlon)
    xyz.y     = (v + height)*cos(radlat)*sin(radlon)
    xyz.z     = (v*(1 - e2) + height)*sin(radlat)

    return xyz
end

local minx              = 1000000
local maxx              = -1000000
local miny              = 1000000
local maxy              = -1000000
local minxtile          = minx
local minytile          = miny

-- determine pixel position for a coordinate relative to the tileimage
-- where it is drawn on
--- calculates pixel coordinates inside the corresponding tile
-- TODO
function M:pixelPosForCoordinates ( lat, lon, zoom, minxtile, minytile )
    -- Logger.warn("pixposforcoords, lat:", lat, " long:", lon, " zoom:", zoom, " minxtile:", minxtile, " minytile:", minytile)
    local xtile, ytile = self:getTileNumber( lat, lon, zoom )
    -- Logger.warn("xtile+ytile:", xtile, " (", ytile, ")", " minxtile: ", minxtile, " minytile: ", minytile)

    -- offset is the pixel coordinates inside the local tile
    -- 256: tilesize
    local xoffset = (xtile - minxtile ) * 256
    local yoffset = (ytile - minytile ) * 256

    local  south, west, north, east = M.Project( xtile, ytile, zoom )

    local x = math.floor( ( lon - west ) * 256 /  ( east - west ) + xoffset )
    local y = math.floor( ( lat - north ) * 256 / ( south - north ) + yoffset )

    if ( x > maxx ) then maxx = x end
    if ( x < minx ) then minx = x end
    if ( y > maxy ) then maxy = y end
    if ( y < miny ) then miny = y end

    return  x, y
end

-- todo
function M.ProjectMercToLat(MercY)
    return 180 / PI * atan(math.sinh(MercY))
end

-- todo
function M.Project (X, Y, Zoom)
    local Unit  = 1 / ( 2 ^ Zoom )
    local relY1 = Y * Unit
    local relY2 = relY1 + Unit

    -- # note: $LimitY = ProjectF(degrees(atan(math.sinh(pi)))) = log(math.sinh(pi)+cosh(pi)) = pi
    -- # note: degrees(atan(math.sinh(pi))) = 85.051128..
    -- #local LimitY = ProjectF(85.0511}

    -- # so stay simple and more accurate
    local LimitY = PI
    local RangeY = 2 * LimitY
    relY1 = LimitY - RangeY * relY1
    relY2 = LimitY - RangeY * relY2

    local Lat1 = M.ProjectMercToLat(relY1)
    local Lat2 = M.ProjectMercToLat(relY2)

    Unit = 360 / ( 2 ^ Zoom )

    local Long1 = -180 + X * Unit
    return  Lat2, Long1, Lat1, Long1 + Unit  -- S,W,N,E
end




function M.test()
    print ("AppState Lat:", appState.current.Location.latitude, " long:",
        appState.current.Location.longitude)
    -- ;!J!
    home = {  lat=appState.current.Location.latitude,
        lon=appState.current.Location.longitude,
        height=M.feet2meters(5280), zoom=16
    }

    print(table.show(M.coord2tile(home.zoom, home.lat, home.lon), "coords to tile:"))
    print(table.show(M.getTileNumber(home.lat, home.lon, home.zoom), "getTileNumber:"))

    x,y,z = M.deg2num(home.lon, home.lat, home.zoom)
    print("deg2num:", x, ",", y, ",", z)
    print(table.show(M.num2deg(35746, 22720, 1), "num2deg:"))

    print("-- home --")
    print("lat = " .. home.lat)
    print("lon = " .. home.lon)

    print("\n-- home coord2tile --")
    tile = M.coord2tile(14, home.lat, home.lon)
    print("lat       = " .. home.lat)
    print("lon       = " .. home.lon)
    print("worldu    = " .. tile.worldu)
    print("worldv    = " .. tile.worldv)
    print("x         = " .. tile.x)
    print("y         = " .. tile.y)
    print("ix        = " .. tile.ix)
    print("iy        = " .. tile.iy)
    print("subtileix = " .. tile.subtileix)
    print("subtileiy = " .. tile.subtileiy)
    print("subtileu  = " .. tile.subtileu)
    print("subtilev  = " .. tile.subtilev)

    print("\n-- home coord2time at zoom --")
    for i=0,14 do
        tile = M.coord2tile(i, home.lat, home.lon)
        print(i .. ": ix =" .. tile.ix        .. ", iy =" .. tile.iy)
        print(i .. ": six=" .. tile.subtileix .. ", siy=" .. tile.subtileiy)
    end

    print("\n-- home tile2coord --")
    coord = M.tile2coord(14, tile.x, tile.y)
    print("x      = " .. tile.x)
    print("y      = " .. tile.y)
    print("worldu = " .. coord.worldu)
    print("worldv = " .. coord.worldv)
    print("lat    = " .. coord.lat)
    print("lon    = " .. coord.lon)

    print("\n-- home coord2xyz --")
    xyz = M.coord2xyz(home.lat, home.lon, home.height)
    print("lat    = " .. home.lat)
    print("lon    = " .. home.lon)
    print("height = " .. home.height)
    print("x      = " .. xyz.x)
    print("y      = " .. xyz.y)
    print("z      = " .. xyz.z)

    print("\n-- mgm sample-per-degree at home --")
    smgm = M.NUMSUBTILE*M.NUMSUBSAMPLEMGM
    for i=1,15 do
        tile0 = M.coord2tile(i, 40, -106)
        tile1 = M.coord2tile(i, 41, -105)
        print(i .. ": dx=" .. smgm*(tile1.x - tile0.x) .. ", dy=" .. smgm*(tile0.y - tile1.y))
    end

    print("\n-- mgm sample-per-degree at equator --")
    for i=1,15 do
        tile0 = M.coord2tile(i, -0.5, -0.5)
        tile1 = M.coord2tile(i, 0.5, 0.5)
        print(i .. ": dx=" .. smgm*(tile1.x - tile0.x) .. ", dy=" .. smgm*(tile0.y - tile1.y))
    end

    print("\n-- ned sample-per-degree at home --")
    sned = M.NUMSUBTILE*M.NUMSUBSAMPLENED
    for i=1,15 do
        tile0 = M.coord2tile(i, 40, -106)
        tile1 = M.coord2tile(i, 41, -105)
        print(i .. ": dx=" .. sned*(tile1.x - tile0.x) .. ", dy=" .. sned*(tile0.y - tile1.y))
    end

    print("\n-- ned sample-per-degree at equator --")
    for i=1,15 do
        tile0 = M.coord2tile(i, -0.5, -0.5)
        tile1 = M.coord2tile(i, 0.5, 0.5)
        print(i .. ": dx=" .. sned*(tile1.x - tile0.x) .. ", dy=" .. sned*(tile0.y - tile1.y))
    end

end

-----------------------------

return M


