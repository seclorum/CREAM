-- Lua script for "CountsYerBoats" game using LuaJIT (Lua 5.1)
-- Integrates boat_groups table to map player boat counts to terms (e.g., Flotilla, Fleet)
-- Plots player boat counts with initials as markers, alongside all boat_groups terms for reference
-- Text-based interface for selecting players and updating boat counts
-- Game loop rotates through players, updates scores, and plots with full boat_groups scale

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

-- Define players table with names and initial boat counts
local players = {
    { name = "Player One", boats = 5 },
    { name = "Player Two", boats = 10 }
}

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

    -- Map reference points (boat_groups terms) to grid with 'o' marker
    local num_terms = #refs_data + #players_data
    for i, point in ipairs(refs_data) do
        local x = math.floor((point.x / max_x) * (term_width - 1)) + 1
        local y = term_height - math.floor((i - 1) * (term_height - 1) / (num_terms - 1))
        if x >= 1 and x <= term_width and y >= 1 and y <= term_height then
            grid[y][x] = "o" -- Reference points marked with 'o'
        end
    end

    -- Map player points to grid with their initials
    for i, point in ipairs(players_data) do
        local x = math.floor((point.x / max_x) * (term_width - 1)) + 1
        local y = term_height - math.floor((#refs_data + i - 1) * (term_height - 1) / (num_terms - 1))
        if x >= 1 and x <= term_width and y >= 1 and y <= term_height then
            grid[y][x] = point.marker -- Use player's initial as marker
        end
    end

    -- Print plot
    print(title)
    print("Y: Index | X: Number of Boats (0 to " .. max_x .. ")")
    print("(* = Players, o = Reference Terms)")
    local all_terms = {}
    for i, point in ipairs(refs_data) do
        table.insert(all_terms, { term = point.term, x = point.x })
    end
    for i, point in ipairs(players_data) do
        table.insert(all_terms, { term = point.term .. " (" .. get_boat_term(point.x) .. ")", x = point.x })
    end
    for y = 1, term_height do
        local row = ""
        for x = 1, term_width do
            row = row .. grid[y][x]
        end
        local idx = math.floor((term_height - y) * (num_terms - 1) / (term_height - 1)) + 1
        if idx <= #all_terms then
            row = row .. "  " .. all_terms[idx].term .. " (" .. all_terms[idx].x .. " boats)"
        end
        print(row)
    end
    local x_axis = string.rep("-", term_width)
    print(x_axis)
    local x_labels = "0" .. string.rep(" ", math.floor(term_width / 2) - 1) .. math.floor(max_x / 2) .. string.rep(" ", term_width - math.floor(term_width / 2) - 2) .. max_x
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
    local term_width = 70    -- Plot width in characters
    local term_height = 15   -- Plot height (should be >= number of players + boat_groups terms)
    
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
-- Plots all boat_groups terms as reference points ('o') alongside player points ('*')
-- Player points use initials (e.g., 'P' for Player One) for identification
-- Labels show player names with corresponding boat_groups term and boat count
-- Generalized plot_ascii function accepts separate player and reference data for flexibility
-- Terminal clearing uses 'clear'; for Windows, replace with 'cls' if needed
-- Adjust max_boats, term_width, term_height for larger/smaller games or terminals
-- Players table supports N entries; add more players by extending the table
-- Future graph types can be added by modifying plot_ascii (e.g., bar, line)
