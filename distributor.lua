--[[
recipesData:
A table containing the layout and quantities of recipes.

Structure:
recipesData = {
    layouts = {
        ["recipeName1"] = {
            [slotId1] = "rawName1",
            [slotId2] = "rawName2",
            ...
        },
        ["recipeName2"] = {
            [slotId1] = "rawName3",
            [slotId2] = "rawName4",
            ...
        },
        ...
    },
    quantities = {
        ["recipeName1"] = {
            ["rawName1"] = quantity1,
            ["rawName2"] = quantity2,
            ...
        },
        ["recipeName2"] = {
            ["rawName3"] = quantity3,
            ["rawName4"] = quantity4,
            ...
        },
        ...
    }
}

Example:
recipesData = {
    layouts = {
        ["iron_plate"] = {
            [1] = "iron_ingot",
            [2] = "iron_ingot",
            ...
        },
        ["gold_plate"] = {
            [1] = "gold_ingot",
            [2] = "gold_ingot",
            ...
        }
    },
    quantities = {
        ["iron_plate"] = {
            ["iron_ingot"] = 2
        },
        ["gold_plate"] = {
            ["gold_ingot"] = 2
        }
    }
}

currentChestData:
A table containing the items and their quantities in the chest.

Structure:
currentChestData = {
    items = {
        [slotId1] = {
            count = itemCount1,
            rawName = "rawName1"
        },
        [slotId2] = {
            count = itemCount2,
            rawName = "rawName2"
        },
        ...
    },
    quantities = {
        ["rawName1"] = totalQuantity1,
        ["rawName2"] = totalQuantity2,
        ...
    }
}

Example:
currentChestData = {
    items = {
        [1] = {
            count = 10,
            rawName = "iron_ingot"
        },
        [2] = {
            count = 5,
            rawName = "gold_ingot"
        }
    },
    quantities = {
        ["iron_ingot"] = 10,
        ["gold_ingot"] = 5
    }
}
]]
-- Check for the existence of a Tech Reborn Rolling Machine and a Minecraft Chest on any of the 6 sides of the computer
local peripherals = peripheral.getNames()
local rollingMachineID = "techreborn:rolling_machine"
local bufferID = "minecraft:chest"

local devices = {
    rollingMachine = {
        side = nil,
        ref = nil
    },
    buffer = {
        side = nil,
        ref = nil
    }
}


for _, name in ipairs(peripherals) do
    if peripheral.getType(name) == rollingMachineID then
        print("Success: Tech Reborn Rolling Machine found on the " .. name .. " side.")
        devices.rollingMachine.side = name
        devices.rollingMachine.ref = peripheral.wrap(name)
    elseif peripheral.getType(name) == bufferID then
        print("Success: Minecraft Chest found on the " .. name .. " side.")
        devices.buffer.side = name
        devices.buffer.ref = peripheral.wrap(name)
    end
end

for deviceName, device in pairs(devices) do
    if not device.ref then
        error("Fail: " .. deviceName .. " not found on any side.")
    end
end

-- Load recipesLayouts from file
local recipesFile = "recipes.json"
local recipesData = {
    layouts = {},
    quantities = {}
}

if fs.exists(recipesFile) then
    local file = fs.open(recipesFile, "r")
    recipesData.layouts = textutils.unserialize(file.readAll())
    file.close()
else
    local file = fs.open(recipesFile, "w")
    file.write(textutils.serialize(recipesData.layouts))
    file.close()
end

-- Process recipesLayouts to gather requirements
for name, layout in pairs(recipesData.layouts) do
    local requirements = {}
    for _, rawName in pairs(layout) do
        if rawName then
            requirements[rawName] = (requirements[rawName] or 0) + 1
        end
    end
    recipesData.quantities[name] = requirements
end

print("Recipes and their requirements loaded successfully.")


-- Check the chest for its content
local function fetchBufferData(bufferReference)
    local bufferRawContent = bufferReference.list()
    local bufferItems = {}
    local bufferQuantities = {}

    for slot, item in pairs(bufferRawContent) do
        local item = bufferReference.getItem(slot)
        local rawName = item.getMetadata().rawName
        local count = item.getMetadata().count
        bufferItems[slot] = { count = count, rawName = rawName }
        bufferQuantities[rawName] = (bufferQuantities[rawName] or 0) + count
    end

    return { items = bufferItems, quantities = bufferQuantities }
end

-- Check if any recipe is suitable for the chest content
local function isRecipeSuitable(recipeQuantities, bufferQuantities)
    for rawName, requiredQuantity in pairs(recipeQuantities) do
        local availableQuantity = bufferQuantities[rawName]
        if not availableQuantity or availableQuantity % requiredQuantity ~= 0 then
            return false
        end
    end
    return true
end

local function fetchSuitableRecipeName(allRecipesQuantities, bufferQuantities)
    for recipeName, recipeQuantities in pairs(allRecipesQuantities) do
        if isRecipeSuitable(recipeQuantities, bufferQuantities) then
            return recipeName
        end
    end
    return nil
end

local function getTableLength(table)
    local count = 0
    for _ in pairs(table) do count = count + 1 end
    return count
end

local function isStorageCapableEmpty(storageReference)
    return getTableLength(storageReference.list()) == 0
end

local ecoSleepDuration = 10         -- seconds
local intermediateSleepDuration = 1 -- seconds
local intermediateSleepAttempts = 5 -- attempts
local workingSleepDuration = 0.5    -- seconds

local sleepManager = {
    ecoModeCounter = 0,
    isActive = false,
    storageReference = devices.buffer.ref
}

function sleepManager:activateWorkingMode()
    self.ecoModeCounter = intermediateSleepAttempts
    self.isActive = true
end

function sleepManager:activateEcoMode()
    self.isActive = false
end

function sleepManager:decrementEcoCounter()
    self.ecoModeCounter = self.ecoModeCounter - 1
end

function sleepManager:sleep()
    if isStorageCapableEmpty(self.storageReference) then
        if self.ecoModeCounter <= 0 then
            self:activateEcoMode()
            print("Entering eco mode. Sleeping for " .. ecoSleepDuration .. " seconds.")
            os.sleep(ecoSleepDuration)
        else
            self:decrementEcoCounter()
            print("Intermediate sleep. Counter: " ..
            self.ecoModeCounter .. ". Sleeping for " .. intermediateSleepDuration .. " seconds.")
            os.sleep(intermediateSleepDuration)
        end
    else
        self:activateWorkingMode()
        print("Working mode. Sleeping for " .. workingSleepDuration .. " seconds.")
        os.sleep(workingSleepDuration)
    end
    return self.isActive
end

local capturingBufferManager = {
    bufferReference = devices.buffer.ref,
    bufferSide = devices.buffer.side,
}
function capturingBufferManager:capture()
    local capturedBufferManager = {
        bufferSide = devices.buffer.side,
        bufferData = fetchBufferData(self.bufferReference)
    }
    function capturedBufferManager:seekItem(rawName)
        local items = self.bufferData.items
        for bufferSlot, itemData in pairs(items) do
            if itemData.rawName == rawName then
                local referencedItem = {
                    rawName = itemData.rawName,
                    count = itemData.count,
                }
                function referencedItem:decrement()
                    self.count = self.count - 1
                    if self.count == 0 then
                        items[bufferSlot] = nil
                    end
                end

                return referencedItem
            end
        end
        return nil
    end

    return capturedBufferManager
end

local rollingMachineManager = {
    machineReference = devices.rollingMachine.ref,
}

while true do
    local isWorking = sleepManager:sleep()
    if isWorking then
        local capturedBuffer = capturingBufferManager:capture()
        local recipeName = fetchSuitableRecipeName(
            recipesData.quantities,
            capturedBuffer.bufferData.quantities
        )
        if recipeName then
            local layout = recipesData.layouts[recipeName]
            -- decrementation test
            local foundItem = capturedBuffer:seekItem(layout[1])
            assert(foundItem ~= nil, "Check seek method, it's broken!")
            for step = 1, foundItem.count do
                print(capturedBuffer.bufferData.items)
                foundItem:decrement()
            end
            print("Final print")
            print(capturedBuffer.bufferData.items)
        end
    end
end
