LOGGING = true
ECHO = true

_ = ECHO and io.write("Fetching peripherals... ")
local peripherals = peripheral.getNames()
_ = ECHO and print("Fetched!")

local rollingMachineID = "techreborn:rolling_machine"
_ = ECHO and print("Rolling Machine ID is set to: " .. rollingMachineID)

local bufferID = "minecraft:chest"
_ = ECHO and print("Buffer ID is set to: " .. bufferID)

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

_ = ECHO and print("[ DeviceDefinition ] Stage started")
for _, name in ipairs(peripherals) do
    if peripheral.getType(name) == rollingMachineID then
        _ = ECHO and print("[ DeviceDefinition ] [ SUCCESS ]: Tech Reborn Rolling Machine found on the " .. name .. " side.")
        devices.rollingMachine.side = name
        devices.rollingMachine.ref = peripheral.wrap(name)
    elseif peripheral.getType(name) == bufferID then
        _ = ECHO and print("[ DeviceDefinition ] [ SUCCESS ]: Buffer found on the " .. name .. " side.")
        devices.buffer.side = name
        devices.buffer.ref = peripheral.wrap(name)
    end
end

for deviceName, device in pairs(devices) do
    if not device.ref then
        error("[ DeviceDefinition ] [ ERROR ]: " .. deviceName .. " is not found.")
    end
end
_ = ECHO and print("[ DeviceDefinition ] Stage completed")

-- Load recipesLayouts from file
local recipesFile = "recipes.json"
local recipesData = {
    layouts = {},
    quantities = {}
}

_ = ECHO and print("[ RecipeLoader ] Stage started")
_ = ECHO and io.write("[ RecipeLoader ] [ " .. recipesFile .. " ] Searching ")
if fs.exists(recipesFile) then
    _ = ECHO and io.write("> Found > Opening ")
    local file = fs.open(recipesFile, "r")

    _ = ECHO and io.write("> Reading & Serializing layouts ")
    recipesData.layouts = textutils.unserialize(file.readAll())

    _ = ECHO and print("> Closing")
    file.close()
else
    _ = ECHO and io.write("> Not Found > Creating ")
    local file = fs.open(recipesFile, "w")

    _ = ECHO and io.write("> Writing ")
    file.write(textutils.serialize(recipesData.layouts))

    _ = ECHO and print("> Closing")
    file.close()
end


-- Process recipesLayouts to gather requirements
_ = ECHO and print("[ RecipeLoader ] Generating requirements for recipes")
for name, layout in pairs(recipesData.layouts) do
    _ = ECHO and io.write("[ RecipeLoader ] [ Recipe: " .. name .. " ] Calculating... ")
    local requirements = {}
    for _, rawName in pairs(layout) do
        if rawName then
            requirements[rawName] = (requirements[rawName] or 0) + 1
        end
    end
    _ = ECHO and print("Done!")
    recipesData.quantities[name] = requirements
end

_ = ECHO and print("[ RecipeLoader ] Stage completed")

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

_ = ECHO and print("[ Main ] Stage started")
-- Sleep manager

local ecoSleepDuration = 10            -- seconds
local inertStateSleepDuration = 1      -- seconds
local inertStateAttempts = 5           -- attempts
local workingSleepDuration = 0.25      -- seconds
local betweenStateSleepDuration = 0.75 -- seconds
local betweenStateAttempts = 10        -- attempts
_ = ECHO and print("[ Main ] Initialized sleep manager constants")

_ = ECHO and io.write("[ Main ] Initializing sleep manager... ")
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
            _ = ECHO and print("State: Working")
            os.sleep(workingSleepDuration)
            if self.betweenstateModeCounter <= 0 then
                self:rechargeBetweenState()
            end
        elseif self:betweenStateCountdown() then
            _ = ECHO and print("State: Between State")
            os.sleep(betweenStateSleepDuration)
        end
        if self.inertModeCounter <= 0 then
            self:rechargeInertState()
        end
    elseif self:inertStateCountdown() then
        _ = ECHO and print("State: Inert State")
        os.sleep(inertStateSleepDuration)
    else
        _ = ECHO and print("State: Eco Mode")
        os.sleep(ecoSleepDuration)
        if isRecipeMatched then
            self:rechargeBetweenState()
        end
    end
end

sleepManager:rechargeInertState()
sleepManager:rechargeBetweenState()
_ = ECHO and print("Done!")


_ = ECHO and io.write("[ Main ] Initializing capturing buffer manager... ")
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
_ = ECHO and print("Done!")

_ = ECHO and io.write("[ Main ] Initializing rolling machine manager... ")
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

_ = ECHO and print("Done!")

_ = ECHO and print("[ Main ] Stage completed")

_ = ECHO and print("[ Main ] Entering main loop")
while true do
    _ = LOGGING and print("[ LOG ] [ MainLoop ] Iteration started... ")
    _ = LOGGING and print("[ LOG ] [ MainLoop ] Checking buffer... ")
    local isEmpty = isStorageCapableEmpty(devices.buffer.ref)
    _ = LOGGING and print("[ LOG ] [ MainLoop ] Buffer is " .. (not isEmpty and "not " or "") .. "empty.")

    local isRecipeMatched = false
    if not isEmpty then
        _ = LOGGING and print("[ LOG ] [ MainLoop ] Capturing buffer... ")
        local capturedBuffer = capturingBufferManager:capture()
        _ = LOGGING and print("[ LOG ] [ MainLoop ] Buffer captured.")

        _ = LOGGING and print("[ LOG ] [ MainLoop ] Fetching suitable recipe... ")
        local recipeName = fetchSuitableRecipeName(
            recipesData.quantities,
            capturedBuffer.bufferData.quantities
        )
        _ = LOGGING and print("[ LOG ] [ MainLoop ] Suitable recipe is " .. (recipeName or "not found") .. ".")

        if recipeName then
            local _sameRecipe = function()
                _ = LOGGING and
                print("[ LOG ] [ MainLoop ] Recipe is the same as previous: loading without interruption")
            end
            local _waitingForEmpty = function()
                _ = LOGGING and
                print("[ LOG ] [ MainLoop ] Recipe is different from previous: waiting for the machine to be empty")
            end
            if rollingMachineManager.previousRecipe == recipeName or isStorageCapableEmpty(devices.rollingMachine.ref) then
                if LOGGING and rollingMachineManager.previousRecipe ~= recipeName then
                    _waitingForEmpty()
                else
                    _sameRecipe()
                end

                _ = LOGGING and print("[ LOG ] [ MainLoop ] Loading \""..recipeName.."\" layout...")
                local layout = recipesData.layouts[recipeName]

                _ = LOGGING and print("[ LOG ] [ MainLoop ] Loading slot managers...")
                local definedSlots = rollingMachineManager:loadSlotManagers(layout)
                for slot, slotManager in pairs(definedSlots) do
                    _ = LOGGING and print("[ LOG ] [ MainLoop ] Receiving item \""..slotManager.itemData.rawName.."\" to slot "..slot)
                    slotManager:receive(capturedBuffer)
                end
                _ = LOGGING and print("[ LOG ] [ MainLoop ] Recipe loaded.")
            end
            isRecipeMatched = true
        end
    end

    _ = LOGGING and print("[ LOG ] [ MainLoop ] Updating sleep manager...")
    sleepManager:updateBufferState(isEmpty, isRecipeMatched)

    _ = LOGGING and print("[ LOG ] [ MainLoop ] Sleeping...")
    sleepManager:sleep()
end
