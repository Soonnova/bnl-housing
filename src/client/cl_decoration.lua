isDecorating = false
currentFocusEntity = nil
currentCamera = nil
isMenuOpen = false

local disabledKeys = {
    0, 1, 2, 3, 4, 5, 6, 7, 8,
    14, 15, 16, 17, 21, 22, 23,
    24, 25, 26, 30, 31, 32, 33,
    34, 35, 36, 37, 38, 44, 46
}

local function StartDisableControlLoop()
    return CreateThread(function()
        repeat 
            Wait(1)

            for _,v in pairs(disabledKeys) do
                DisableControlAction(0, v, isDecorating)
            end
        until not isDecorating

        -- Reset the disabled keys
        for _,v in pairs(disabledKeys) do
            DisableControlAction(0, v, isDecorating)
        end
    end)
end

local function GetLocationForCameraRotation(rotation, location, offset)
    local aplha = math.rad(rotation.z - 90)
    local x = location.x + (math.cos(aplha) * offset)
    local y = location.y + (math.sin(aplha) * offset)

    local beta = math.rad(rotation.x - 90)
    local z = location.z - (math.cos(beta) * offset)

    return vec3(x, y, z)
end

local function InitCamera(coord)
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamActive(camera, true)
    RenderScriptCams(true, true, 1000, true, true)
    SetCamRot(camera, 0.0, 0.0, 0.0)
    SetCamCoord(camera, GetLocationForCameraRotation(vec3(0,0,0), coord + vec3(0,0,1), 2.5))

    return camera
end

local function CanRotateCam()
    return
            not IsPauseMenuActive()
        and not isMenuOpen
end

local function StartCameraLoop(smallRotate)
    if (smallRotate == nil) then
        smallRotate = false
    end
    return CreateThread(function()
        local currentDistance = 2.5
        local minDistance = 0.5
        local maxDistance = 5.0
        repeat 
            Wait(10)
            if (currentCamera) then
                local horizontal = 0
                local vertical = 0
                local sensitivity = 5

                if (not smallRotate and not CanRotateCam()) then goto continue end

                -- Rotation Calculation
                if (GetDisabledControlNormal(0, 1) ~= 0) then
                    horizontal = GetDisabledControlNormal(0, 1) * -sensitivity
                end
                
                if (smallRotate) then horizontal = horizontal + 0.5 end

                if (GetDisabledControlNormal(0, 2) ~= 0) then
                    vertical = GetDisabledControlNormal(0, 2) * -sensitivity
                end

                -- Distance Calculation
                if (GetDisabledControlNormal(0, 14) ~= 0) then
                    currentDistance = currentDistance + (GetDisabledControlNormal(0, 14) * 0.5)
                end
                if (GetDisabledControlNormal(0, 15) ~= 0) then
                    currentDistance = currentDistance - (GetDisabledControlNormal(0, 15) * 0.5)
                end
                currentDistance = math.min(maxDistance, math.max(minDistance, currentDistance))

                local currentRotation = GetCamRot(currentCamera, 2)
                local newRotation = currentRotation + vec3(vertical, 0, horizontal)
                newRotation = vec3(math.min(85, math.max(-85, newRotation.x)), newRotation.y, newRotation.z)

                local newLocation = GetLocationForCameraRotation(newRotation, GetEntityCoords(currentFocusEntity), currentDistance)
                if (smallRotate) then newLocation = newLocation + vec3(0,0,1) end
                SetCamCoord(currentCamera, newLocation)
                SetCamRot(currentCamera, newRotation.x, 0.0, newRotation.z, 2, true)
                
                ::continue::
            end
        until not isDecorating

        -- reset the camera
        SetCamActive(camera, false)
        RenderScriptCams(false, true, 1000, true, true)
    end)
end

local function SetupPlayer()
    StartDisableControlLoop()
    
    SetEntityVisible(cache.ped, false)
    DisplayRadar(false)
end

local function InitObject(prop, coords)
    object = CreateObjectNoOffset(prop, coords, false, false, false)
    FreezeEntityPosition(object, true)
    SetEntityCollision(object, false, false)
    return object
end

local function GetPropCategory()
    local Promise = promise.new()

    local categories = {}
    for k,v in pairs(props) do
        table.insert(categories, k)
    end
    table.sort(categories, function(a, b) return a < b end)

    lib.registerMenu({
        id = 'decoration_category',
        title = 'Choose a category',
        onClose = function()
            Promise:resolve('')
        end,
        options = {
            { label = 'Category', values = categories },
        }
    }, function(selected, scrollIndex, args)
        Promise:resolve(categories[scrollIndex])
    end)
    lib.showMenu('decoration_category')

    local result = Citizen.Await(Promise)
    return result
end

local function ConfirmPropLocation()
    local shellCoord = GetEntityCoords(shellObject)
    local propCoord = shellCoord - GetEntityCoords(currentFocusEntity)

    TriggerServerEvent('bnl-housing:decoration:saveProp', {
        x = propCoord.x,
        y = propCoord.y,
        z = propCoord.z,
        w = GetEntityHeading(currentFocusEntity),
        model = currentFocusModel
    })

    AddPropMenu()
end

local isMovingProp = false
local propMoveSpeed = 0.25
function StartMovePropLoop()
    isMovingProp = true

    local location
    CreateThread(function()
        repeat
            Wait(5)

            local forwardbackward = (GetDisabledControlNormal(0, 31) / 10) * propMoveSpeed
            local rightleft = (GetDisabledControlNormal(0, 30) / 10) * propMoveSpeed * -1
            local updown = 0
            updown = updown + (GetDisabledControlNormal(0, 44) / 10) * propMoveSpeed
            updown = updown - (GetDisabledControlNormal(0, 46) / 10) * propMoveSpeed
            local rotation = 0
            rotation = rotation + GetControlNormal(0, 174) * propMoveSpeed
            rotation = rotation + GetControlNormal(0, 175) * propMoveSpeed * -1

            location = GetEntityCoords(currentFocusEntity)
            local forwardVector, rightVector, _, position = GetEntityMatrix(currentFocusEntity)
            local newPosition = location + (forwardbackward * forwardVector) + (rightleft * rightVector) + (updown * vec3(0,0,1))
            local newHeading = GetEntityHeading(currentFocusEntity) + rotation

            SetEntityCoords(currentFocusEntity, newPosition)
            SetEntityCoords(cache.ped, newPosition)
            SetEntityHeading(currentFocusEntity, newHeading)

            local furtherPosition = location - forwardVector * propMoveSpeed
            DrawLine(location.x, location.y, location.z, furtherPosition.x, furtherPosition.y, furtherPosition.z, 255, 0, 0, 255)
            
            if (IsControlJustReleased(0, 176)) then
                ConfirmPropLocation()
                isMovingProp = false
            end

            if (IsControlJustReleased(0, 177)) then
                AddPropMenu()
            end

            if (IsDisabledControlJustReleased(0, 22)) then
                propMoveSpeed = propMoveSpeed * 2
                if (propMoveSpeed > 3) then
                    propMoveSpeed = 0.02
                end
                print(("Set prop move speed to: %s"):format(propMoveSpeed))
            end
        until not isMovingProp
    end)
end

function AddPropMenu()
    local category = props[GetPropCategory()]
    if (not category) then return OpenMainMenu() end

    local coord = GetEntityCoords(cache.ped)
    currentFocusEntity = InitObject(category[1], coord)

    local propsList = {}
    for k,v in pairs(category) do
        table.insert(propsList, v)
    end
    table.sort(propsList, function(a, b) return a < b end)

    isMenuOpen = true
    SetupPlayer()

    lib.registerMenu({
        id = 'decoration_prop',
        title = 'Prop Menu',
        onSideScroll = function(selected, scrollIndex, args)
            if (currentFocusEntity) then DeleteEntity(currentFocusEntity) end
            local object = propsList[scrollIndex]
            currentFocusEntity = InitObject(object, coord)
            currentFocusModel = object
        end,
        onClose = function()
            isMenuOpen = false
            if (currentFocusEntity) then DeleteEntity(currentFocusEntity) end
            OpenMainMenu()
        end,
        options = {
            { label = 'Prop', values = propsList },
            { label = 'Change Location', icon = 'location-crosshairs' },
        }
    }, function(selected, scrollIndex, args)
        isMenuOpen = false
        
        -- move prop loop
        if (selected == 1) then
            isMenuOpen = false
            if (currentFocusEntity) then DeleteEntity(currentFocusEntity) end
            OpenMainMenu()
        end

        if (selected == 2) then
            StartMovePropLoop()
        end
    end)
    lib.showMenu('decoration_prop')

    currentCamera = InitCamera(coord)
    StartCameraLoop()
end

function EditPropMenu()
    if (type(propertyPlayerIsIn.decoration) == 'string') then
        propertyPlayerIsIn.decoration = json.decode(propertyPlayerIsIn.decoration)
    end

    local entities = {}
    for _, prop in pairs(propertyPlayerIsIn.decoration) do
        local worldCoords = GetEntityCoords(shellObject) - vector3(prop.x, prop.y, prop.z)
        local entity = GetClosestObjectOfType(worldCoords, 0.5, GetHashKey(prop.model))
        entities[entity] = prop

        if (not entity) then
            Logger.Error(('Could not find prop: #%s'):format(prop.id))
        end
    end

    local menuItems = {}
    for entityId, prop in pairs(entities) do
        table.insert(menuItems, entityId)
    end

    isMenuOpen = true
    isDecorating = true
    SetupPlayer()

    lib.registerMenu({
        id = 'decoration_editprop',
        title = 'Edit Prop Menu',
        onSideScroll = function(selected, scrollIndex, args)
            SetEntityDrawOutline(currentFocusEntity, false)
            local entity = menuItems[scrollIndex]
            currentFocusEntity = entity
            SetEntityDrawOutline(currentFocusEntity, true)
            SetEntityDrawOutlineColor(255, 192, 0, 255)
            currentCamera = InitCamera(GetEntityCoords(entity))
        end,
        onClose = function()
            isMenuOpen = false
            SetEntityDrawOutline(currentFocusEntity, false)
            OpenMainMenu()
        end,
        options = {
            { label = 'Select Prop', values = menuItems },
        }
    }, function(selected, scrollIndex, args)
    end)
    lib.showMenu('decoration_editprop')
    
    StartCameraLoop(true)
end

function OpenMainMenu()
    isMenuOpen = true

    lib.registerMenu({
        id = 'decorating_menu',
        title = locale('decoration_menu'),
        onClose = function()
            StopDecorating()
        end,
        options = {
            { label = 'Create a prop', icon = 'plus' },
            { label = 'Edit a prop', icon = 'edit' },
            { label = 'Remove a prop', icon = 'remove' },
        }
    }, function(selected, scrollIndex, args)
        if (selected == 1) then
            -- Add prop menu
            AddPropMenu()
        elseif (selected == 2) then
            -- Edit prop menu
            EditPropMenu()
        elseif (selected == 3) then
            -- Remove prop menu
        end
    end)
    lib.showMenu('decorating_menu')
end

local startDecoratingCoord
function StartDecorating()
    if (propertyPlayerIsIn and propertyPlayerIsIn.shell.disable_decorate) then
        -- this property can't be decorated
        return
    end
    
    isDecorating = true
    startDecoratingCoord = GetEntityCoords(cache.ped) - vec3(0,0,1)
    OpenMainMenu()
end

function StopDecorating()
    isDecorating = false

    SetEntityCoords(cache.ped, startDecoratingCoord)
    SetEntityVisible(cache.ped, true)
    DisplayRadar(true)
end

AddEventHandler('bnl-housing:client:decorate', StartDecorating)
AddEventHandler('bnl-housing:client:stopdecorate', StopDecorating)

function FocusEntity(entity)
    -- set the focus to the entity
    currentFocusEntity = entity
end