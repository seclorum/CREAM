-- Lua script to plot boat group terms in a terminal using ASCII art for LuaJIT (Lua 5.1 compatibility)
-- Uses a simple custom ASCII plotting approach since 'lua-plot' is not compatible with LuaJIT
-- X-axis: Number of boats (scaled to fit terminal width)
-- Y-axis: Term index (1 to #terms, spaced vertically)
-- Plots points as '*' with term labels next to them
-- Note: Terminal width is assumed to be ~80 characters; adjust 'term_width' if needed

-- Define the boat_groups table as provided
local boat_groups = {
    [1] = { term = "Single", description = "One boat, operating alone, not part of a coordinated group." },
    [2] = { term = "Pair", description = "Two boats sailing together, often informally or for a minor coordinated effort." },
    [5] = { term = "Group", description = "A small, informal collection of 3–7 boats, often seen in casual sailing or small regattas." },
    [10] = { term = "Flotilla", description = "A modest group of 5–15 boats, often coordinated for a regatta, parade, or patrol." },
    [15] = { term = "Division", description = "A naval or regatta subgroup of 10–20 boats, often a subset of a larger fleet or race class." },
    [20] = { term = "Squadron", description = "A naval term for 10–30 boats, typically similar types (e.g., racing yachts or patrol craft) under unified command." },
    [25] = { term = "Regatta", description = "A competitive event with 10–40 boats, typically sailboats or rowing boats, racing together." },
    [30] = { term = "Convoy", description = "A group of 15–45 boats, often merchant or civilian, traveling together for safety or coordination." },
    [40] = { term = "Fleet", description = "A large collection of 20–60 boats, common in major regattas or naval operations." },
    [50] = { term = "Task Force", description = "A naval term for 30–70 boats assembled for a specific mission, often temporary." },
    [100] = { term = "Armada", description = "A historical term for a massive group of 60+ boats, often used for large fleets or dramatic effect." }
}

-- Configuration for terminal plot
local term_width = 70  -- Width of plot area in characters (excluding labels)
local term_height = 15 -- Height of plot area in lines (should be >= number of terms)
local max_boats = 100  -- Maximum X-axis value (largest number of boats)
local num_terms = 0    -- Count of terms for Y-axis

-- Collect data for plotting
local data = {}
for num_boats, info in pairs(boat_groups) do
    num_terms = num_terms + 1
    table.insert(data, { x = num_boats, term = info.term })
end

-- Sort data by Y-index (insertion order) for consistent plotting
table.sort(data, function(a, b) return a.x < b.x end)

-- Create a 2D grid for ASCII plot
local grid = {}
for y = 1, term_height do
    grid[y] = {}
    for x = 1, term_width do
        grid[y][x] = " " -- Initialize grid with spaces
    end
end

-- Map data points to grid
for i, point in ipairs(data) do
    -- Scale X-coordinate (number of boats) to fit terminal width
    local x = math.floor((point.x / max_boats) * (term_width - 1)) + 1
    -- Assign Y-coordinate based on index (reverse to start from bottom)
    local y = term_height - math.floor((i - 1) * (term_height - 1) / (num_terms - 1))
    -- Ensure coordinates are within bounds
    if x >= 1 and x <= term_width and y >= 1 and y <= term_height then
        grid[y][x] = "*" -- Mark point with '*'
    end
end

-- Print the plot
print("Boat Group Terms by Number of Boats")
print("Y: Term Index | X: Number of Boats (0 to 100)")

-- Print grid with labels
for y = 1, term_height do
    local row = ""
    for x = 1, term_width do
        row = row .. grid[y][x]
    end
    -- Add label for the corresponding Y-index
    local idx = math.floor((term_height - y) * (num_terms - 1) / (term_height - 1)) + 1
    if idx <= #data then
        row = row .. "  " .. data[idx].term
    end
    print(row)
end

-- Print X-axis labels
local x_axis = string.rep("-", term_width)
print(x_axis)
local x_labels = "0" .. string.rep(" ", math.floor(term_width / 2) - 1) .. "50" .. string.rep(" ", term_width - math.floor(term_width / 2) - 2) .. "100"
print(x_labels)

-- Notes:
-- Adjust 'term_width' and 'term_height' for your terminal size
-- If plot is too dense, increase 'term_width' or reduce 'max_boats'
-- Labels are printed to the right; ensure terminal is wide enough (>80 chars recommended)
-- This is a basic ASCII plot; for more advanced plotting, consider a LuaJIT-compatible graphical library like 'luasdl2' or redirecting output to a file for external plotting
