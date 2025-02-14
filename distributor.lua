io.write("Fetching peripherals... ")
local peripherals = peripheral.getNames()
print("Fetched!")

local rollingMachineID = "techreborn:rolling_machine"
print("Rolling Machine ID is set to: " .. rollingMachineID)

local bufferID = "minecraft:chest"
print("Buffer ID is set to: " .. bufferID)

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

print("[ DeviceDefinition ] Stage started")
for _, name in ipairs(peripherals) do
    if peripheral.getType(name) == rollingMachineID then
        print("[ DeviceDefinition ] [ SUCCESS ]: Tech Reborn Rolling Machine found on the " .. name .. " side.")
        devices.rollingMachine.side = name
        devices.rollingMachine.ref = peripheral.wrap(name)
    elseif peripheral.getType(name) == bufferID then
        print("[ DeviceDefinition ] [ SUCCESS ]: Buffer found on the " .. name .. " side.")
        devices.buffer.side = name
        devices.buffer.ref = peripheral.wrap(name)
    end
end

for deviceName, device in pairs(devices) do
    if not device.ref then
        error("[ DeviceDefinition ] [ ERROR ]: " .. deviceName .. " is not found.")
    end
end
print("[ DeviceDefinition ] Stage completed")

-- Load recipesLayouts from file
local recipesFile = "recipes.json"
local recipesData = {
    layouts = {},
    quantities = {}
}

print("[ RecipeLoader ] Stage started")
io.write("[ RecipeLoader ] [ "..recipesFile.." ] Seearching ")
if fs.exists(recipesFile) then
    io.write("> Found > Opening ")
    local file = fs.open(recipesFile, "r")

    io.write("> Reading & Serializing layouts ")
    recipesData.layouts = textutils.unserialize(file.readAll())

    print("> Closing")
    file.close()
else
    io.write("> Not Found > Creating ")
    local file = fs.open(recipesFile, "w")

    io.write("> Writing ")
    file.write(textutils.serialize(recipesData.layouts))

    print("> Closing")
    file.close()
end


-- Process recipesLayouts to gather requirements
print("[ RecipeLoader ] Generating requirements for recipes")
for name, layout in pairs(recipesData.layouts) do
    io.write("[ RecipeLoader ] [ Recipe: "..name.." ] Calculating... ")
    local requirements = {}
    for _, rawName in pairs(layout) do
        if rawName then
            requirements[rawName] = (requirements[rawName] or 0) + 1
        end
    end
    print("Done!")
    recipesData.quantities[name] = requirements
end

print("[ RecipeLoader ] Stage completed")

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

print("[ Main ] Stage started")
-- Sleep manager

local ecoSleepDuration = 10            -- seconds
local inertStateSleepDuration = 1      -- seconds
local inertStateAttempts = 5           -- attempts
local workingSleepDuration = 0.25      -- seconds
local betweenStateSleepDuration = 0.75 -- seconds
local betweenStateAttempts = 10        -- attempts
print("[ Main ] Initialized sleep manager constants")

io.write("[ Main ] Iniializing sleep manager... ")
local sleepManager = {
    inertModeCounter = 0,
    betweenstateModeCounter = 0,
    observableStates = {
        isEmpty = true,
        isRecipeMatched = false,
    }
}


function sleepManager:inertStateCountdown()
    if not self.inertModeCounter > 0 then
        return false
    end
    self.inertModeCounter = self.inertModeCounter - 1
    return true
end

function sleepManager:rechargeBetweenState()
    self.betweenstateModeCounter = betweenStateAttempts
end

function sleepManager:rechargeInertState()
    self.inertModeCounter = inertStateAttempts
end

function sleepManager:betweenStateCountdown()
    if not self.betweenstateModeCounter > 0 then
        return false
    end
    self.betweenstateModeCounter = self.betweenstateModeCounter - 1
    return true
end

function sleepManager:updateBufferState(isEmpty, isRecipeMatched)
    self.observableStates.isEmpty = isEmpty
    self.observableStates.isRecipeMatched = isRecipeMatched
end

function sleepManager:sleep()
    local isEmpty = self.observableStates.isEmpty
    local isRecipeMatched = self.observableStates.isRecipeMatched
    if not isEmpty and self.betweenstateModeCounter > 0 then
        if isRecipeMatched then
            print("State: Working")
            os.sleep(workingSleepDuration)
            if self.betweenstateModeCounter <= 0 then
                self:rechargeBetweenState()
            end
        elseif self:betweenStateCountdown() then
            print("State: Between State")
            os.sleep(betweenStateSleepDuration)
        end
        if self.inertModeCounter <= 0 then
            self:rechargeInertState()
        end
    elseif self:inertStateCountdown() then
        print("State: Inert State")
        os.sleep(inertStateSleepDuration)
    else
        print("State: Eco Mode")
        os.sleep(ecoSleepDuration)
        if isRecipeMatched then
            self:rechargeBetweenState()
        end
    end
end

sleepManager:rechargeInertState()
sleepManager:rechargeBetweenState()
print("Done!")


io.write("[ Main ] Initializing capturing buffer manager... ")
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
                local itemLink = {
                    slot = bufferSlot,
                    item = itemData,
                }
                function itemLink:decrement()
                    self.item.count = self.item.count - 1
                    if self.item.count == 0 then
                        items[bufferSlot] = nil
                    end
                end

                return itemLink
            end
        end
        return nil
    end

    return capturedBufferManager
end

local function devicePullItems(deviceReference, fromSide, fromSlot, count, toSlot)
    assert(deviceReference, "Error: Device reference is nil.")
    assert(fromSide, "Error: Source side is nil.")
    assert(fromSlot, "Error: Source slot is nil.")
    assert(count, "Error: Item count is nil.")
    assert(toSlot, "Error: Destination slot is nil.")
    return deviceReference.pullItems(fromSide, fromSlot, count, toSlot)
end
print("Done!")

io.write("[ Main ] Initializing rolling machine manager... ")
local rollingMachineManager = {
    machineReference = devices.rollingMachine.ref,
    previousRecipe = nil,
}

function rollingMachineManager:loadSlotManagers(receipeLayout)
    local definedMachineSlots = {}
    local ref = self.machineReference
    for machineSlot, itemRawName in pairs(receipeLayout) do
        local definedSlot = {
            itemData = nil,
        }
        function definedSlot:receive(capturedBM)
            local bufferItemLink = capturedBM:seekItem(itemRawName)
            local transfered = devicePullItems(ref, capturedBM.bufferSide, bufferItemLink.slot, 1, machineSlot)
            assert(transfered ~= 0, "Can't transfer item" .. bufferItemLink.item.rawName)
            bufferItemLink:decrement()
        end

        definedMachineSlots[machineSlot] = definedSlot
    end
    return definedMachineSlots
end
print("Done!")

print("[ Main ] Stage completed")

print("[ Main ] Entering main loop")
while true do
    local isEmpty = isStorageCapableEmpty(devices.buffer.ref)
    local isRecipeMatched = false
    if not isEmpty then
        local capturedBuffer = capturingBufferManager:capture()
        local recipeName = fetchSuitableRecipeName(
            recipesData.quantities,
            capturedBuffer.bufferData.quantities
        )
        if recipeName then
            if rollingMachineManager.previousRecipe == recipeName or isStorageCapableEmpty(devices.rollingMachine.ref) then
                local layout = recipesData.layouts[recipeName]
                local definedSlots = rollingMachineManager:loadSlotManagers(layout)
                for _, slotManager in pairs(definedSlots) do
                    slotManager:receive(capturedBuffer)
                end
            end
            isRecipeMatched = true
        end
    end
    sleepManager:updateBufferState(isEmpty, isRecipeMatched)
    sleepManager:sleep()
end
