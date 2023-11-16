
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

function M.feet2meters(feet)
    return feet*1609.344/5280.0
end

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
    tile.x         = tile.worldu*(2^zoom)/NUMSUBTILE
    tile.y         = tile.worldv*(2^zoom)/NUMSUBTILE
    tile.ix        = floor(tile.x)
    tile.iy        = floor(tile.y)
    tile.subtilex  = NUMSUBTILE*(tile.x - tile.ix)
    tile.subtiley  = NUMSUBTILE*(tile.y - tile.iy)
    tile.subtileix = floor(tile.subtilex)
    tile.subtileiy = floor(tile.subtiley)
    tile.subtileu  = tile.subtilex - tile.subtileix
    tile.subtilev  = tile.subtiley - tile.subtileiy

    return tile
end

function M.tile2coord(zoom, tilex, tiley)
    local coord  = { }
    coord.worldu = NUMSUBTILE*tilex/(2^zoom)
    coord.worldv = NUMSUBTILE*tiley/(2^zoom)
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


function M.test()
    home = { lat=40.061295, lon=-105.214552, height=feet2meters(5280) }

    --Logger.debug("-- home --")
    --Logger.debug("lat = " .. home.lat)
    --Logger.debug("lon = " .. home.lon)

    --Logger.debug("\n-- home coord2tile --")
    tile = coord2tile(14, home.lat, home.lon)
    --Logger.debug("lat       = " .. home.lat)
    --Logger.debug("lon       = " .. home.lon)
    --Logger.debug("worldu    = " .. tile.worldu)
    --Logger.debug("worldv    = " .. tile.worldv)
    --Logger.debug("x         = " .. tile.x)
    --Logger.debug("y         = " .. tile.y)
    --Logger.debug("ix        = " .. tile.ix)
    --Logger.debug("iy        = " .. tile.iy)
    --Logger.debug("subtileix = " .. tile.subtileix)
    --Logger.debug("subtileiy = " .. tile.subtileiy)
    --Logger.debug("subtileu  = " .. tile.subtileu)
    --Logger.debug("subtilev  = " .. tile.subtilev)

    --Logger.debug("\n-- home coord2time at zoom --")
    for i=0,14 do
        tile = coord2tile(i, home.lat, home.lon)
        --Logger.debug(i .. ": ix =" .. tile.ix        .. ", iy =" .. tile.iy)
        --Logger.debug(i .. ": six=" .. tile.subtileix .. ", siy=" .. tile.subtileiy)
    end

    --Logger.debug("\n-- home tile2coord --")
    coord = tile2coord(14, tile.x, tile.y)
    --Logger.debug("x      = " .. tile.x)
    --Logger.debug("y      = " .. tile.y)
    --Logger.debug("worldu = " .. coord.worldu)
    --Logger.debug("worldv = " .. coord.worldv)
    --Logger.debug("lat    = " .. coord.lat)
    --Logger.debug("lon    = " .. coord.lon)

    --Logger.debug("\n-- home coord2xyz --")
    xyz = coord2xyz(home.lat, home.lon, home.height)
    --Logger.debug("lat    = " .. home.lat)
    --Logger.debug("lon    = " .. home.lon)
    --Logger.debug("height = " .. home.height)
    --Logger.debug("x      = " .. xyz.x)
    --Logger.debug("y      = " .. xyz.y)
    --Logger.debug("z      = " .. xyz.z)

    --Logger.debug("\n-- mgm sample-per-degree at home --")
    smgm = NUMSUBTILE*NUMSUBSAMPLEMGM
    for i=1,15 do
        tile0 = coord2tile(i, 40, -106)
        tile1 = coord2tile(i, 41, -105)
        --Logger.debug(i .. ": dx=" .. smgm*(tile1.x - tile0.x) .. ", dy=" .. smgm*(tile0.y - tile1.y))
    end

    --Logger.debug("\n-- mgm sample-per-degree at equator --")
    for i=1,15 do
        tile0 = coord2tile(i, -0.5, -0.5)
        tile1 = coord2tile(i, 0.5, 0.5)
        --Logger.debug(i .. ": dx=" .. smgm*(tile1.x - tile0.x) .. ", dy=" .. smgm*(tile0.y - tile1.y))
    end

    --Logger.debug("\n-- ned sample-per-degree at home --")
    sned = NUMSUBTILE*NUMSUBSAMPLENED
    for i=1,15 do
        tile0 = coord2tile(i, 40, -106)
        tile1 = coord2tile(i, 41, -105)
        --Logger.debug(i .. ": dx=" .. sned*(tile1.x - tile0.x) .. ", dy=" .. sned*(tile0.y - tile1.y))
    end

    --Logger.debug("\n-- ned sample-per-degree at equator --")
    for i=1,15 do
        tile0 = coord2tile(i, -0.5, -0.5)
        tile1 = coord2tile(i, 0.5, 0.5)
        --Logger.debug(i .. ": dx=" .. sned*(tile1.x - tile0.x) .. ", dy=" .. sned*(tile0.y - tile1.y))
    end

end
