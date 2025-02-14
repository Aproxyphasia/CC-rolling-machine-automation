-- Check for the existence of a Tech Reborn Rolling Machine on any of the 6 sides of the computer
local peripherals = peripheral.getNames()
local rollingMachine

for _, name in ipairs(peripherals) do
    if peripheral.getType(name) == "techreborn:rolling_machine" then
        print("Success: Tech Reborn Rolling Machine found on the " .. name .. " side.")
        rollingMachine = peripheral.wrap(name)
        break
    end
end

if not rollingMachine then
    error("Fail: Tech Reborn Rolling Machine not found on any side.")
end

-- local textutils and fs are directly accessible

local recipesFile = "recipes.json"
local recipes = {}

-- Load recipes from file
if fs.exists(recipesFile) then
    local file = fs.open(recipesFile, "r")
    recipes = textutils.unserialize(file.readAll())
    file.close()
else
    local file = fs.open(recipesFile, "w")
    file.write(textutils.serialize(recipes))
    file.close()
end

local function saveRecipes()
    local file = fs.open(recipesFile, "w")
    file.write(textutils.serialize(recipes))
    file.close()
end

local function storeRecipe(name)
    local layout = {}
    for slotId = 1, 9 do
        local item = rollingMachine.getItem(slotId)
        layout[slotId] = item and item.getMetadata().rawName or nil
    end

    print("Recipe layout:")
    for slotId, rawName in pairs(layout) do
        print("Slot " .. slotId .. ": " .. (rawName or "Empty"))
    end

    print("Are you sure you want to store this recipe? (Y/N)")
    local input = read()
    if input:lower() == "y" then
        if recipes[name] then
            print("Recipe with this name already exists. Overwrite? (Y/N)")
            input = read()
            if input:lower() ~= "y" then
                return
            end
        end
        recipes[name] = layout
        saveRecipes()
        print("Recipe stored successfully.")
    else
        print("Operation cancelled.")
    end
end

local function deleteRecipe(name)
    if not recipes[name] then
        print("Recipe not found.")
        return
    end

    print("Are you sure you want to delete this recipe? (Y/N)")
    local input = read()
    if input:lower() == "y" then
        recipes[name] = nil
        saveRecipes()
        print("Recipe deleted successfully.")
    else
        print("Operation cancelled.")
    end
end

local function viewRecipe(name)
    local recipe = recipes[name]
    if not recipe then
        print("Recipe not found.")
        return
    end

    print("Recipe layout:")
    for slotId, rawName in pairs(recipe) do
        print("Slot " .. slotId .. ": " .. (rawName or "Empty"))
    end
end

local function listRecipes(page)
    local recipeNames = {}
    for name in pairs(recipes) do
        table.insert(recipeNames, name)
    end
    table.sort(recipeNames)

    local itemsPerPage = 5
    local totalPages = math.ceil(#recipeNames / itemsPerPage)

    if page < 1 or page > totalPages then
        print("Invalid page number.")
        return
    end

    print("Recipes (Page " .. page .. " of " .. totalPages .. "):")
    for i = (page - 1) * itemsPerPage + 1, math.min(page * itemsPerPage, #recipeNames) do
        print(recipeNames[i])
    end
end

local function printHelp()
    print("Available commands:")
    print("store [name] - Stores the current layout as a recipe with the given name.")
    print("list [page] - Lists the names of saved recipes, 5 per page.")
    print("view [name] - Views the recipe with the given name.")
    print("del [name] - Deletes the recipe with the given name.")
    print("help - Displays this help message.")
    print("exit - Exits the program.")
end

while true do
    print("Enter command:")
    local input = read()
    local command, arg = input:match("^(%S+)%s*(.*)$")

    if command == "store" then
        if arg and arg ~= "" then
            storeRecipe(arg)
        else
            print("Usage: store [name]")
        end
    elseif command == "list" then
        local page = tonumber(arg)
        if page then
            listRecipes(page)
        else
            print("Usage: list [page]")
        end
    elseif command == "view" then
        if arg and arg ~= "" then
            viewRecipe(arg)
        else
            print("Usage: view [name]")
        end
    elseif command == "del" then
        if arg and arg ~= "" then
            deleteRecipe(arg)
        else
            print("Usage: del [name]")
        end
    elseif command == "help" then
        printHelp()
    elseif command == "exit" then
        print("Exiting program.")
        break
    else
        print("Unknown command. Type 'help' for a list of commands.")
    end
end
