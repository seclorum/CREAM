local posix = require("posix")

local M = {}

-- get difference between local time and UTC in [s]
function M:getUTCDiff_s()
    local now = os.time()
    local utc = os.date( "!*t", now )
    local lcl = os.date( "*t", now )

    -- if local has dst set it to false and change now for difftime
    -- we want the total difference
    if lcl.isdst then
        lcl.isdst = false
        now = os.time( lcl )
    end

    local unow = os.time( utc )

    local diff = os.difftime( now, unow )

    return diff
end

-- takes a timestamp in local time and prints the corresponding UTC string
function M:toUTCString( timestamp )
    -- get offset to UTC
    -- local t_diff_s = pl.Date.tzone()
    local t_diff_s = self:getUTCDiff_s()
    -- create UTC timestamp from input
    local utc_ts = timestamp - t_diff_s

    local utc_str = os.date( "%Y-%m-%dT%H:%M:%S.000Z",utc_ts )

    return utc_str
end

-- returns posix time in miliseconds from monotonic clock
function M:LOCALgetMilis()
	local tv_sec, tv_nsec = posix.clock_gettime("CLOCK_MONOTONIC")
	local milis = tv_sec*1e+3 + tv_nsec/1e+6
	return milis
end
return M
