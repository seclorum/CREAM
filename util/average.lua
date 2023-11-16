-- Various average (means) algorithms implementation
-- See: http://en.wikipedia.org/wiki/Average

-- Returns the sum of a sequence of values
local function sum(x)
    local s = 0
    for _, v in ipairs(x) do s = s + v end
    return s
end

-- Calculates the arithmetic mean of a set of values
-- x       : an array of values
-- returns : the arithmetic mean
local function arithmetic_mean(x)
    return (sum(x) / #x)
end

-- Calculates the geometric mean of a set of values
-- x       : an array of values
-- returns : the geometric mean
local function geometric_mean(x)
    local prod = 1
    for _, v in ipairs(x) do prod = prod * v end
    return (prod ^ (1 / #x))
end

-- Calculates the harmonic mean of a set of values
-- x       : an array of values
-- returns : the harmonic mean
local function harmonic_mean(x)
    local s = 0
    for _, v in ipairs(x) do s = s + (1 / v) end
    return (#x / s)
end

-- Calculates the quadratic mean of a set of values
-- x       : an array of values
-- returns : the quadratic mean
local function quadratic_mean(x)
    local ssquares = 0
    for _, v in ipairs(x) do ssquares = ssquares + (v * v) end
    return math.sqrt((1 / #x) * ssquares)
end

-- Calculates the generalized mean (to a specified power p) of a set of values
-- x       : an array of values
-- p       : a power
-- returns : the generalized mean
local function generalized_mean(x, p)
    local sump = 0
    for _, v in ipairs(x) do sump = sump + (v ^ p) end
    return ((1 / #x) * sump) ^ (1 / p)
end

-- Calculates the weighted mean of a set of values
-- x       : an array of values
-- w       : an array of weights for each value in x
-- returns : the weighted mean
local function weighted_mean(x, w)
    local sump = 0
    for i, v in ipairs (x) do sump = sump + (v * w[i]) end
    return sump / sum(w)
end

-- Calculates the midrange mean of a set of values
-- x       : an array of values
-- returns : the midrange mean
local function midrange_mean(x)
    local sump = 0
    return 0.5 * (math.min(unpack(x)) + math.max(unpack(x)))
end

-- Calculates the energetic mean of a set of values
-- x       : an array of values
-- returns : the energetic mean
local function energetic_mean(x)
    local s = 0
    for _,v in ipairs(x) do s = s + (10 ^ (v / 10)) end
    return 10 * math.log10((1 / #x) * s)
end


-- Calculates the moving average of a set of values over a given window
-- t          : an array of values
-- lowerLimit : distance to lower range of the window to be averaged
-- higherLimit: distance to upper range of the window to be avergage
-- returns: the averaged array of the input set
local function moving_average(t, lowerLimit, upperLimit)
    local averraged = {}
    for i,v in ipairs(t) do
        local tempSum = 0
        for n=i-lowerLimit,i+upperLimit, 1 do
            if not t[n] then
                tempSum = tempSum + 0;
            else
                tempSum = tempSum + t[n]
            end
        end
        averraged[i] = tempSum /(lowerLimit + upperLimit + 1)
    end
    return averraged
end

local function stdandard_dev( t )
    local m
    local vm
    local sum = 0
    local count = 0
    local result

    m = arithmetic_mean( t )

    for k,v in pairs(t) do
        if type(v) == 'number' then
            vm = v - m
            sum = sum + (vm * vm)
            count = count + 1
        end
    end

    result = math.sqrt(sum / (count))

    return result
end


return {
    arithmetic     = arithmetic_mean,
    geometric      = geometric_mean,
    harmonic       = harmonic_mean,
    quadratic      = quadratic_mean,
    generalized    = generalized_mean,
    weighted       = weighted_mean,
    midrange       = midrange_mean,
    energetic      = energetic_mean,
    moving         = moving_average,
    std_deviation  = stdandard_dev
}
