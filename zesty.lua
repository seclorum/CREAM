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
  }
}

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
    </div>
  </body>
  </html>
]]

-- Mustache template for a fruit detail page
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
  -- Prepare data for Mustache: convert fruits table to a list with IDs
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

-- TurboLua application with prioritized routes
local app = turbo.web.Application:new({
  -- Specific route for /fruit/:id comes first
  {"/fruit/(%d+)", FruitHandler},
  -- Catch-all for homepage
  {"/.*", HomeHandler}
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
