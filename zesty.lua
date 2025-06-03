-- a mockup model for reference in CREAM
-- Require TurboLua for web server and Mustache templating
local turbo = require("turbo")
local mustache = require("turbo.web").Mustache

-- Logging function with timestamp for tracking application state
local function log(message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  print(string.format("[%s] %s", timestamp, message))
end

-- Fruits table using ID as key for O(1) lookups
local fruits = {
  ["1"] = {
    name = "Zesty Zapfruit",
    brief = "A vibrant, electric citrus with a shocking tang.",
    details = {
      origin = "Tropical highlands of Zestoria",
      flavor = "Tart, tangy, with a fizzy aftertaste",
      description = "The Zapfruit is a rare citrus hybrid, known for its neon yellow rind and pulsating flavor that tingles the tongue. Perfect for adventurous palates!",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="#FFD700" /><path d="M50 20 L60 40 L40 40 Z" fill="#FF4500" /></svg>'
    }
  },
  ["2"] = {
    name = "Flamingo Fizzel",
    brief = "A pink, effervescent fruit with a sassy kick.",
    details = {
      origin = "Flamingo Isles",
      flavor = "Sweet-tart with a bubbly zing",
      description = "This flamboyant fruit grows in coastal groves, its rosy flesh bursting with effervescence. A favorite for tropical cocktails.",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><ellipse cx="50" cy="50" rx="40" ry="30" fill="#FF69B4" /><rect x="45" y="30" width="10" height="20" fill="#FFFFFF" /></svg>'
    }
  },
  ["3"] = {
    name = "Tangerine Tornado",
    brief = "A whirlwind of citrusy spice and zest.",
    details = {
      origin = "Spiral Valleys",
      flavor = "Spicy, citrusy, with a warm finish",
      description = "The Tangerine Tornado swirls with fiery orange hues and a bold, spicy flavor that leaves a lasting impression.",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="#FF8C00" /><path d="M50 10 A40 40 0 0 1 90 50 A40 40 0 0 1 50 90" fill="none" stroke="#DC143C" stroke-width="5" /></svg>'
    }
  },
  ["4"] = {
    name = "Lime Lightning",
    brief = "A sharp, electrifying burst of green zest.",
    details = {
      origin = "Thunderbolt Jungles",
      flavor = "Sour, crisp, with a zesty jolt",
      description = "Lime Lightning is a small but mighty fruit, its vivid green flesh delivering a sour punch that energizes any dish.",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="35" fill="#00FF00" /><path d="M50 20 L40 50 L60 30 L40 70 L60 50" fill="none" stroke="#FFFF00" stroke-width="5" /></svg>'
    }
  },
  ["5"] = {
    name = "Pomegranate Pop",
    brief = "A ruby-red explosion of juicy zest.",
    details = {
      origin = "Crimson Plains",
      flavor = "Sweet, tart, with a juicy burst",
      description = "Pomegranate Pop is a jewel-like fruit, its arils bursting with sweet-tart juice that’s both refreshing and bold.",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="#C71585" /><circle cx="45" cy="45" r="10" fill="#FFFFFF" /><circle cx="55" cy="55" r="10" fill="#FFFFFF" /></svg>'
    }
  },
  ["6"] = {
    name = "Nutritious Nuttikins",
    brief = "Rugged, woody nuggets bursting with zesty nutrients.",
    details = {
      origin = "Ancient groves of Forest Deep",
      flavor = "Nutty, zesty, with a smoky warmth that sparks the palate",
      description = "Nutritious Nuttikins are elusive treasures of the forest, their gnarled, woody shells hiding a vibrant, nutrient-packed core. Their smoky zest can ignite both your taste buds and, legend says, a campfire in a pinch!",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><ellipse cx="50" cy="50" rx="40" ry="30" fill="#8B4513" /><path d="M30 50 C30 60, 70 60, 70 50 S50 40, 30 50" fill="#228B22" /><path d="M45 45 L55 55 M55 45 L45 55" stroke="#FFD700" stroke-width="3" /></svg>'
    }
  },
  ["7"] = {
    name = "The Ball Sack Of a Succulent Gourd",
    brief = "A juicy, bulbous gourd with a cheeky charm.",
    details = {
      origin = "Mystic Gourd Gardens",
      flavor = "Sweet, succulent, with a playful burst",
      description = "This audacious gourd dangles from the vines of the Mystic Gourd Gardens, its plump, juicy flesh bursting with sweet succulence and a hint of mischief.",
      svg = '<svg width="100" height="100" viewBox="0 0 100 100"><ellipse cx="50" cy="60" rx="40" ry="30" fill="#4B0082" /><circle cx="50" cy="40" r="20" fill="#32CD32" /><path d="M40 60 C40 70, 60 70, 60 60" fill="#98FB98" /><circle cx="45" cy="65" r="5" fill="#FFFFFF" /><circle cx="55" cy="65" r="5" fill="#FFFFFF" /></svg>'
    }
  }
}

-- Default SVG for new fruits if none provided
local default_svg = '<svg width="100" height="100" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" fill="#CCCCCC" /><text x="50" y="55" font-size="20" text-anchor="middle" fill="#000000">?</text></svg>'

-- Mustache template for the homepage
local home_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Zesty Fruits</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f4f4f4; }
    h1 { text-align: center; color: #333; }
    .fruit-list { display: flex; flex-wrap: wrap; gap: 20px; justify-content: center; }
    .fruit-card { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); width: 200px; text-align: center; }
    .fruit-card a { color: #0066cc; text-decoration: none; font-weight: bold; }
    .fruit-card a:hover { text-decoration: underline; }
    .action-card { background: #e6f3ff; padding: 15px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); width: 200px; text-align: center; }
    .action-card a, .action-card form button { color: #0066cc; text-decoration: none; font-weight: bold; background: none; border: none; cursor: pointer; }
    .action-card a:hover, .action-card form button:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>Zesty Fruits</h1>
  <div class="fruit-list">
    {{#fruits}}
    <div class="fruit-card">
      <h3><a href="/fruit/{{id}}">{{name}}</a></h3>
      <p>{{brief}}</p>
    </div>
    {{/fruits}}
    <div class="action-card">
      <h3><a href="/add">Add New Fruit</a></h3>
      <p>Create a new zesty fruit</p>
    </div>
    <div class="action-card">
      <form action="/export" method="GET">
        <h3><button type="submit">Export Fruits</button></h3>
        <p>Download fruits table as Lua</p>
      </form>
    </div>
    <div class="action-card">
      <h3><a href="/import">Import Fruits</a></h3>
      <p>Upload a fruits table</p>
    </div>
  </div>
</body>
</html>
]]

-- Mustache template for the add fruit form
local add_fruit_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Add New Fruit</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f4f4f4; }
    .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    h1 { color: #333; text-align: center; }
    form { display: flex; flex-direction: column; gap: 15px; }
    label { font-weight: bold; }
    input, textarea { width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; }
    textarea { height: 100px; }
    button { background: #0066cc; color: white; padding: 10px; border: none; border-radius: 4px; cursor: pointer; }
    button:hover { background: #0055aa; }
    a { color: #0066cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .error { color: red; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Add New Fruit</h1>
    {{#error}}
    <p class="error">{{error}}</p>
    {{/error}}
    <form method="POST" action="/add" enctype="application/x-www-form-urlencoded">
      <label for="id">ID (unique number):</label>
      <input type="number" name="id" required>
      <label for="name">Name:</label>
      <input type="text" name="name" required>
      <label for="brief">Brief Description:</label>
      <input type="text" name="brief" required>
      <label for="origin">Origin:</label>
      <input type="text" name="origin" required>
      <label for="flavor">Flavor:</label>
      <input type="text" name="flavor" required>
      <label for="description">Description:</label>
      <textarea name="description" required></textarea>
      <label for="svg">SVG (optional):</label>
      <textarea name="svg"></textarea>
      <button type="submit">Add Fruit</button>
    </form>
    <p><a href="/">Back to Home</a></p>
  </div>
</body>
</html>
]]

-- Mustache template for the import fruits form
local import_fruit_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Import Fruits</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f4f4f4; }
    .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    h1 { color: #333; text-align: center; }
    form { display: flex; flex-direction: column; gap: 15px; }
    label { font-weight: bold; }
    input[type="file"] { padding: 8px; }
    button { background: #0066cc; color: white; padding: 10px; border: none; border-radius: 4px; cursor: pointer; }
    button:hover { background: #0055aa; }
    a { color: #0066cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .error { color: red; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Import Fruits</h1>
    {{#error}}
    <p class="error">{{error}}</p>
    {{/error}}
    <form method="POST" action="/import" enctype="multipart/form-data">
      <label for="file">Upload Fruits Lua File:</label>
      <input type="file" name="file" accept=".lua" required>
      <button type="submit">Import Fruits</button>
    </form>
    <p><a href="/">Back to Home</a></p>
  </div>
</body>
</html>
]]

-- Mustache template for fruit detail page
local fruit_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{{name}}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f4f4f4; }
    .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    h1 { color: #333; text-align: center; }
    .svg-container { text-align: center; margin: 20px 0; }
    p { line-height: 1.6; color: #555; }
    a { color: #0066cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <h1>{{name}}</h1>
    <div class="svg-container">{{{svg}}}</div>
    <p><strong>Origin:</strong> {{origin}}</p>
    <p><strong>Flavor:</strong> {{flavor}}</p>
    <p><strong>Description:</strong> {{description}}</p>
    <p><a href="/">Back to Home</a></p>
  </div>
</body>
</html>
]]

-- Mustache template for 404 page
local not_found_template = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Fruit Not Found</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f4f4f4; text-align: center; }
    h1 { color: #333; }
    a { color: #0066cc; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <h1>Fruit Not Found</h1>
  <p><a href="/">Back to Home</a></p>
</body>
</html>
]]

-- Render homepage using Mustache
local function render_home()
  -- Convert fruits table to a list with IDs for Mustache
  local fruit_list = {}
  for id, fruit in pairs(fruits) do
    table.insert(fruit_list, { id = id, name = fruit.name, brief = fruit.brief })
  end
  return mustache.render(home_template, { fruits = fruit_list })
end

-- Render fruit detail page using Mustache
local function render_fruit(fruit)
  if not fruit then
    return mustache.render(not_found_template, {})
  end
  -- Pass fruit details directly to Mustache (svg is unescaped with {{{svg}}})
  return mustache.render(fruit_template, {
    name = fruit.name,
    svg = fruit.details.svg,
    origin = fruit.details.origin,
    flavor = fruit.details.flavor,
    description = fruit.details.description
  })
end

-- Handler for the homepage
local HomeHandler = class("HomeHandler", turbo.web.RequestHandler)
function HomeHandler:get()
  log(string.format("Handling GET request for homepage from %s", self.request.remote_ip or "unknown IP"))
  self:write(render_home())
  log("Homepage rendered successfully")
end

-- Handler for fruit detail pages
local FruitHandler = class("FruitHandler", turbo.web.RequestHandler)
function FruitHandler:get(id)
  log(string.format("Handling GET request for fruit ID %s from %s", id, self.request.remote_ip or "unknown IP"))
  local fruit = fruits[id]
  if fruit then
    log(string.format("Found fruit: %s", fruit.name))
    self:write(render_fruit(fruit))
    log("Fruit detail page rendered successfully")
  else
    log(string.format("Fruit with ID %s not found", id))
    self:set_status(404)
    self:write(render_fruit(nil))
    log("404 page rendered for missing fruit")
  end
end

-- Handler for adding new fruits (GET for form, POST for submission)
local AddFruitHandler = class("AddFruitHandler", turbo.web.RequestHandler)
function AddFruitHandler:get()
  log(string.format("Handling GET request for add fruit form from %s", self.request.remote_ip or "unknown IP"))
  -- Render the add fruit form
  local html = mustache.render(add_fruit_template, {})
  self:write(html)
  log("Add fruit form rendered successfully")
end

function AddFruitHandler:post()
  log(string.format("Handling POST request for add fruit from %s", self.request.remote_ip or "unknown IP"))
  -- Get POST form arguments
  local args = self:get_post_arguments() or {}
  local id = args.id and args.id[1]
  local name = args.name and args.name[1]
  local brief = args.brief and args.brief[1]
  local origin = args.origin and args.origin[1]
  local flavor = args.flavor and args.flavor[1]
  local description = args.description and args.description[1]
  local svg = args.svg and args.svg[1] or default_svg

  -- Validate form inputs
  if not id or not name or not brief or not origin or not flavor or not description then
    log("Validation failed: Missing required fields")
    self:set_status(400)
    local html = mustache.render(add_fruit_template, { error = "All fields except SVG are required" })
    self:write(html)
    log("Add fruit form rendered with error")
    return
  end
  if fruits[id] then
    log(string.format("Validation failed: ID %s already exists", id))
    self:set_status(400)
    local html = mustache.render(add_fruit_template, { error = "ID already exists" })
    self:write(html)
    log("Add fruit form rendered with error")
    return
  end
  if not id:match("^%d+$") then
    log("Validation failed: ID must be a number")
    self:set_status(400)
    local html = mustache.render(add_fruit_template, { error = "ID must be a number" })
    self:write(html)
    log("Add fruit form rendered with error")
    return
  end

  -- Insert new fruit into the table
  fruits[id] = {
    name = name,
    brief = brief,
    details = {
      origin = origin,
      flavor = flavor,
      description = description,
      svg = svg
    }
  }
  log(string.format("Added new fruit: %s with ID %s", name, id))
  -- Redirect to the homepage
  self:redirect("/")
  log("Redirected to homepage after adding fruit")
end

-- Handler for exporting the fruits table as a Lua file
local ExportHandler = class("ExportHandler", turbo.web.RequestHandler)
function ExportHandler:get()
  log(string.format("Handling GET request for export fruits from %s", self.request.remote_ip or "unknown IP"))
  -- Generate Lua table string
  local lua_content = "local fruits = {\n"
  for id, fruit in pairs(fruits) do
    lua_content = lua_content .. string.format([[
  ["%s"] = {
    name = %q,
    brief = %q,
    details = {
      origin = %q,
      flavor = %q,
      description = %q,
      svg = %q
    }
  },
]], id, fruit.name, fruit.brief, fruit.details.origin, fruit.details.flavor, fruit.details.description, fruit.details.svg)
  end
  lua_content = lua_content .. "}\n\nreturn fruits\n"

  -- Set headers for file download
  self:set_header("Content-Type", "text/x-lua")
  self:set_header("Content-Disposition", "attachment; filename=fruits.lua")
  self:write(lua_content)
  log("Fruits table exported as fruits.lua")
end

-- Handler for importing a fruits table from a Lua file
local ImportHandler = class("ImportHandler", turbo.web.RequestHandler)
function ImportHandler:get()
  log(string.format("Handling GET request for import fruits form from %s", self.request.remote_ip or "unknown IP"))
  -- Render the import form
  local html = mustache.render(import_fruit_template, {})
  self:write(html)
  log("Import fruits form rendered successfully")
end

function ImportHandler:post()
  log(string.format("Handling POST request for import fruits from %s", self.request.remote_ip or "unknown IP"))

  -- Get uploaded files
  local files = self.request.files or {}
  local file_data = files.file and files.file[1] and files.file[1].body

  -- Validate file upload
  if not file_data or #file_data == 0 then
    log("Validation failed: No file uploaded or file is empty")
    self:set_status(400)
    local html = mustache.render(import_fruit_template, { error = "Please upload a valid Lua file" })
    self:write(html)
    log("Import fruits form rendered with error")
    return
  end

  -- Save uploaded file temporarily
  local temp_file = os.tmpname()
  local f, err = io.open(temp_file, "w")
  if not f then
    log(string.format("Failed to write temporary file: %s", err))
    self:set_status(500)
    local html = mustache.render(import_fruit_template, { error = "Server error: Unable to process file" })
    self:write(html)
    log("Import fruits form rendered with error")
    return
  end
  f:write(file_data)
  f:close()

  -- Create a sandboxed environment to safely execute the Lua file
  local sandbox_env = {}
  local success, new_fruits = pcall(function()
    -- Load and execute the file in the sandboxed environment
    setfenv(dofile(temp_file), sandbox_env)
    return sandbox_env.fruits
  end)

  -- Clean up the temporary file
  os.remove(temp_file)

  -- Check if the file execution was successful and returned a table
  if not success or type(new_fruits) ~= "table" then
    log(string.format("Validation failed: Lua file did not return a valid table: %s", tostring(new_fruits)))
    self:set_status(400)
    local html = mustache.render(import_fruit_template, { error = "Lua file must return a valid fruits table" })
    self:write(html)
    log("Import fruits form rendered with error")
    return
  end

  -- Validate the structure of the new fruits table
  for id, fruit in pairs(new_fruits) do
    if type(id) ~= "string" or not id:match("^%d+$") or
       type(fruit) ~= "table" or
       type(fruit.name) ~= "string" or
       type(fruit.brief) ~= "string" or
       type(fruit.details) ~= "table" or
       type(fruit.details.origin) ~= "string" or
       type(fruit.details.flavor) ~= "string" or
       type(fruit.details.description) ~= "string" or
       type(fruit.details.svg) ~= "string" then
      log(string.format("Validation failed: Invalid fruit data structure for ID %s", id))
      self:set_status(400)
      local html = mustache.render(import_fruit_template, { error = "Invalid fruit data structure for ID " .. id })
      self:write(html)
      log("Import fruits form rendered with error")
      return
    end
  end

  -- Update the fruits table
  fruits = new_fruits
  log("Successfully imported new fruits table")
  -- Redirect to the homepage
  self:redirect("/")
  log("Redirected to homepage after importing fruits")
end

-- TurboLua application with explicit route definitions
local app = turbo.web.Application:new({
  {"/fruit/(%d+)", FruitHandler}, -- Fruit detail pages
  {"/add", AddFruitHandler}, -- Add fruit form and submission
  {"/export", ExportHandler}, -- Export fruits table
  {"/import", ImportHandler}, -- Import fruits table
  {"^/$", HomeHandler} -- Exact match for homepage
})

-- Log server startup
log("Starting TurboLua server on port 8080")

-- Start the server with error handling
local ioloop = turbo.ioloop.instance()
ioloop:add_callback(function()
  local success, err = pcall(function()
    app:listen(8080)
    log("Server successfully listening on port 8080")
  end)
  if not success then
    log(string.format("Failed to start server: %s", err))
    os.exit(1) -- Exit on failure to bind port
  end
end)

-- Log when the event loop starts
log("Starting event loop")

-- Start the event loop with error handling
local success, err = pcall(function()
  ioloop:start()
end)
if not success then
  log(string.format("Event loop terminated with error: %s", err))
else
  log("Event loop stopped gracefully")
end
