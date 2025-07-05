-- Lua script for "CountsYerBoats" game using LuaJIT (Lua 5.1)
-- Fixes bug where players with same boat count (e.g., 100 boats) overwrite markers
-- Uses iTerm2 dimensions: 132 columns (out of 189) x 32 rows
-- Plots player boat counts with initials alongside all boat_groups terms for reference
-- Ensures unique Y-positions for all points, even with identical X-values
-- Text-based interface for selecting players and updating boat counts

-- Define boat_groups table for mapping boat counts to terms
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

-- Notes:
-- Adjust 'term_width' and 'term_height' for your terminal size
-- If plot is too dense, increase 'term_width' or reduce 'max_boats'
-- Labels are printed to the right; ensure terminal is wide enough (>80 chars recommended)
-- This is a basic ASCII plot; for more advanced plotting, consider a LuaJIT-compatible graphical library like 'luasdl2' or redirecting output to a file for external plotting
-- Define players table with names and initial boat counts
local players = {
    { name = "Player Red", boats = 34 },
    { name = "Player Green", boats = 18 },
    { name = "Player Blue", boats = 80 },
    { name = "Player Orange", boats = 90 }
}


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

-- Function to map boat count to term from boat_groups
local function get_boat_term(boat_count)
    local closest_term = "None"
    local closest_num = math.huge
    for num, info in pairs(boat_groups) do
        if math.abs(num - boat_count) < math.abs(closest_num - boat_count) then
            closest_num = num
            closest_term = info.term
        end
    end
    return closest_term
end

-- Function to get player initial for plot marker
local function get_player_initial(name)
    return string.sub(name, 1, 1):upper() -- First letter of name
end

-- Generalized ASCII plotting function
-- Arguments: players_data (table of {x, term, marker}), refs_data (table of {x, term}), term_width, term_height, max_x, title
local function plot_ascii(players_data, refs_data, term_width, term_height, max_x, title)
    -- Create 2D grid for ASCII plot
    local grid = {}
    for y = 1, term_height do
        grid[y] = {}
        for x = 1, term_width do
            grid[y][x] = " "
        end
    end

    -- Combine all data points
    local all_data = {}
    for _, point in ipairs(refs_data) do
        table.insert(all_data, { x = point.x, term = point.term, marker = "o", is_player = false })
    end
    for _, point in ipairs(players_data) do
        table.insert(all_data, { x = point.x, term = point.term .. " (" .. get_boat_term(point.x) .. ")", marker = point.marker, is_player = true })
    end

    -- Group points by X-value to assign same Y-position
    local x_groups = {}
    for _, point in ipairs(all_data) do
        if not x_groups[point.x] then
            x_groups[point.x] = { markers = {}, terms = {}, has_player = false }
        end
        table.insert(x_groups[point.x].markers, point.marker)
        table.insert(x_groups[point.x].terms, point.term .. " (" .. point.x .. " boats)")
        if point.is_player then
            x_groups[point.x].has_player = true
        end
    end

    -- Convert x_groups to a sorted list of unique X-values
    local unique_x_values = {}
    for x_val in pairs(x_groups) do
        table.insert(unique_x_values, x_val)
    end
    table.sort(unique_x_values)

    -- Check if number of unique X-values exceeds term_height
    local num_unique_x = #unique_x_values
    if num_unique_x > term_height then
        print("Warning: Too many unique boat counts (" .. num_unique_x .. ") for terminal height (" .. term_height .. "). Some points may be clipped.")
    end

    -- Assign Y-positions based on unique X-values
    local assigned_points = {}
    for i, x_val in ipairs(unique_x_values) do
        local x = math.floor((x_val / max_x) * (term_width - 1)) + 1
        -- Spread Y-positions evenly, reversing to start from bottom
        local y = term_height - math.floor((i - 1) * (term_height - 1) / (num_unique_x - 1))
        if x >= 1 and x <= term_width and y >= 1 and y <= term_height then
            -- Prioritize player marker if present, else use reference marker
            local marker = x_groups[x_val].has_player and x_groups[x_val].markers[#x_groups[x_val].markers] or x_groups[x_val].markers[1]
            grid[y][x] = marker
            table.insert(assigned_points, { y = y, terms = x_groups[x_val].terms, x_val = x_val })
        end
    end

    -- Sort assigned points by Y for labeling (top to bottom)
    table.sort(assigned_points, function(a, b) return a.y < b.y end)

    -- Print plot
    print(title)
    print("Y: Index | X: Number of Boats (0 to " .. max_x .. ")")
    print("(* = Players, o = Reference Terms)")
    for y = 1, term_height do
        local row = ""
        for x = 1, term_width do
            row = row .. grid[y][x]
        end
        -- Collect all terms for this row
        local label = ""
        for _, point in ipairs(assigned_points) do
            if point.y == y then
                label = table.concat(point.terms, ", ")
                break
            end
        end
        print(row .. "  " .. (label ~= "" and label or ""))
    end
    local x_axis = string.rep("-", term_width)
    print(x_axis)
    local half_x = math.floor(max_x / 2)
    local x_labels = "0" .. string.rep(" ", math.floor(term_width / 2) - 1) .. half_x .. string.rep(" ", term_width - math.floor(term_width / 2) - string.len(tostring(half_x)) - 1) .. max_x
    print(x_labels)
end

-- Generalized ASCII plotting function
-- Arguments: players_data (table of {x, term, marker}), refs_data (table of {x, term}), term_width, term_height, max_x, title
local function plot_ascii_old(players_data, refs_data, term_width, term_height, max_x, title)
    -- Create 2D grid for ASCII plot
    local grid = {}
    for y = 1, term_height do
        grid[y] = {}
        for x = 1, term_width do
            grid[y][x] = " "
        end
    end

    -- Combine all data points for consistent Y-spacing
    local all_data = {}
    for _, point in ipairs(refs_data) do
        table.insert(all_data, { x = point.x, term = point.term, marker = "o", is_player = false })
    end
    for _, point in ipairs(players_data) do
        table.insert(all_data, { x = point.x, term = point.term .. " (" .. get_boat_term(point.x) .. ")", marker = point.marker, is_player = true })
    end
    -- Sort by X-value (boat count) to handle overlaps, secondary sort by term for consistency
    table.sort(all_data, function(a, b)
        if a.x == b.x then
            return a.term < b.term
        end
        return a.x < b.x
    end)

    -- Map points to grid with unique Y-positions
    local num_terms = #all_data
    for i, point in ipairs(all_data) do
        local x = math.floor((point.x / max_x) * (term_width - 1)) + 1
        local y = term_height - i + 1
        if x >= 1 and x <= term_width and y >= 1 and y <= term_height then
            grid[y][x] = point.marker
        end
    end

    -- Print plot
    print(title)
    print("Y: Index | X: Number of Boats (0 to " .. max_x .. ")")
    print("(* = Players, o = Reference Terms)")
    for y = 1, term_height do
        local row = ""
        for x = 1, term_width do
            row = row .. grid[y][x]
        end
        local idx = term_height - y + 1
        if idx <= #all_data and idx >= 1 then
            row = row .. "  " .. all_data[idx].term .. " (" .. all_data[idx].x .. " boats)"
        end
        print(row)
    end
    local x_axis = string.rep("-", term_width)
    print(x_axis)
    local half_x = math.floor(max_x / 2)
    local x_labels = "0" .. string.rep(" ", math.floor(term_width / 2) - 1) .. half_x .. string.rep(" ", term_width - math.floor(term_width / 2) - string.len(tostring(half_x)) - 1) .. max_x
    print(x_labels)
end

-- Function to display text-based interface for player selection
local function display_interface(players, current_player)
    -- Clear terminal (works on Unix-like systems; for Windows, use "cls")
    os.execute("clear")
    -- Print header
    print("=== CountsYerBoats ===")
    print("Current Players:")
    -- Display players with selection indicator
    for i, player in ipairs(players) do
        local marker = (i == current_player) and "> " or "  "
        local term = get_boat_term(player.boats)
        print(marker .. player.name .. ": " .. player.boats .. " boats (" .. term .. ")")
    end
    print("\nCommands: [n]ext player, [s]et boats, [p]lot, [q]uit")
end

-- Main game loop
local function counts_yer_boats()
    local current_player = 1 -- Start with first player
    local max_boats = 100    -- Max X-axis value for plotting (matches boat_groups max)
    local term_width = 100   -- Plot width in characters (uses 132 of 189 columns, reserving space for labels)
    local term_height = 25   -- Plot height (fits 32-row iTerm2, accommodates players + boat_groups)
    
    while true do
        -- Display interface
        display_interface(players, current_player)
        
        -- Get user input
        io.write("Command: ")
        local input = io.read("*line"):lower()
        
        -- Process commands
        if input == "n" then
            -- Move to next player
            current_player = current_player % #players + 1
        elseif input == "s" then
            -- Set boat count for current player
            io.write("Enter number of boats (0-" .. max_boats .. "): ")
            local count = tonumber(io.read("*line"))
            if count and count >= 0 and count <= max_boats then
                players[current_player].boats = math.floor(count)
            else
                print("Invalid input! Use a number between 0 and " .. max_boats)
                io.read("*line")
            end
        elseif input == "p" then
            -- Prepare data for plotting
            local players_data = {}
            for i, player in ipairs(players) do
                table.insert(players_data, {
                    x = player.boats,
                    term = player.name,
                    marker = get_player_initial(player.name)
                })
            end
            local refs_data = {}
            for num, info in pairs(boat_groups) do
                table.insert(refs_data, { x = num, term = info.term })
            end
            table.sort(refs_data, function(a, b) return a.x < b.x end)
            -- Plot scores with reference terms
            os.execute("clear")
            plot_ascii(players_data, refs_data, term_width, term_height, max_boats, "CountsYerBoats - Player Scores vs. Boat Scale")
            print("\nPress Enter to return to menu...")
            io.read("*line")
        elseif input == "q" then
            -- Quit game
            print("Thanks for playing CountsYerBoats!")
            break
        end
    end
end

-- Start the game
counts_yer_boats()

-- Notes:
-- Uses 132 columns (term_width = 100 for plot + ~32 for labels) out of 189
-- Fixes bug where players with same boat count (e.g., 100 boats) overwrote markers
-- Combines all data (players + boat_groups) into one sorted array for unique Y-positions
-- Players marked with initials (e.g., 'P'), reference terms with 'o'
-- Labels show player names with boat_groups term and boat count
-- Terminal clearing uses 'clear'; for Windows, replace with 'cls' if needed
-- Players table supports N entries; add more players by extending the table
-- Future graph types can be added by modifying plot_ascii (e.g., bar, line)
