local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local isLoggedIn = LocalPlayer.state.isLoggedIn
local playerPed = PlayerPedId()
local playerCoords = GetEntityCoords(playerPed)
local closestCityhall = nil
local inCityhallPage = false
local inRangeCityhall = false
local pedsSpawned = false
local table_clone = table.clone
local blips = {}

-- Functions

local function getClosestHall()
    local distance = #(playerCoords - Config.Cityhalls[1].coords)
    local closest = 1
    for i = 1, #Config.Cityhalls do
        local hall = Config.Cityhalls[i]
        local dist = #(playerCoords - hall.coords)
        if dist < distance then
            distance = dist
            closest = i
        end
    end
    return closest
end

local function setCityhallPageState(bool, message)
    if message then
        local action = bool and "open" or "close"
        SendNUIMessage({
            action = action
        })
    end
    SetNuiFocus(bool, bool)
    inCityhallPage = bool
    if not Config.UseTarget or bool then return end
    inRangeCityhall = false
end

local function createBlip(options)
    if not options.coords or type(options.coords) ~= 'table' and type(options.coords) ~= 'vector3' then return error(('createBlip() expected coords in a vector3 or table but received %s'):format(options.coords)) end
    local blip = AddBlipForCoord(options.coords.x, options.coords.y, options.coords.z)
    SetBlipSprite(blip, options.sprite or 1)
    SetBlipDisplay(blip, options.display or 4)
    SetBlipScale(blip, options.scale or 1.0)
    SetBlipColour(blip, options.colour or 1)
    SetBlipAsShortRange(blip, options.shortRange or false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(options.title or 'No Title Given')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function deleteBlips()
    if not next(blips) then return end
    for i = 1, #blips do
        local blip = blips[i]
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    blips = {}
end

local function initBlips()
    for i = 1, #Config.Cityhalls do
        local hall = Config.Cityhalls[i]
        if hall.showBlip then
            blips[#blips+1] = createBlip({
                coords = hall.coords,
                sprite = hall.blipData.sprite,
                display = hall.blipData.display,
                scale = hall.blipData.scale,
                colour = hall.blipData.colour,
                shortRange = true,
                title = hall.blipData.title
            })
        end
    end
end

local function spawnPeds()
  if not Config.Peds or not next(Config.Peds) or pedsSpawned then return end
  for i = 1, #Config.Peds do
    local current = Config.Peds[i]
    current.model = type(current.model) == 'string' and joaat(current.model) or current.model
    RequestModel(current.model)
    while not HasModelLoaded(current.model) do
      Wait(0)
    end
    local ped = CreatePed(0, current.model, current.coords.x, current.coords.y, current.coords.z - 1, current.coords.w, false, false)
    FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, current.scenario, true, true)
    current.pedHandle = ped
    local opts = nil
    if current.cityhall then
      opts = {
        label = 'Open Cityhall',
        icon = 'fa-solid fa-city',
        action = function()
          inRangeCityhall = true
          setCityhallPageState(true, true)
        end
      }
    end
    if opts then
      exports['qb-target']:AddTargetEntity(ped, {
        options = {opts},
        distance = 2.0
      })
    end
  end
  pedsSpawned = true
end

local function deletePeds()
    if not Config.Peds or not next(Config.Peds) or not pedsSpawned then return end
    for i = 1, #Config.Peds do
        local current = Config.Peds[i]
        if current.pedHandle then
            DeletePed(current.pedHandle)
        end
    end
    pedsSpawned = false
end

-- Events

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    isLoggedIn = true
    spawnPeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    isLoggedIn = false
    deletePeds()
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
end)

RegisterNetEvent('qb-cityhall:client:getIds', function()
    TriggerServerEvent('qb-cityhall:server:getIDs')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deleteBlips()
    deletePeds()
end)

-- NUI Callbacks

RegisterNUICallback('close', function(_, cb)
    setCityhallPageState(false, false)
    cb('ok')
end)

RegisterNUICallback('requestId', function(id, cb)
    local license = Config.Cityhalls[closestCityhall].licenses[id.type]
    if inRangeCityhall and license and id.cost == license.cost then
        TriggerServerEvent('qb-cityhall:server:requestId', id.type, closestCityhall)
    else
        QBCore.Functions.Notify(Lang:t('error.not_in_range'), 'error')
    end
    cb('ok')
end)

RegisterNUICallback('requestLicenses', function(_, cb)
    local licensesMeta = PlayerData.metadata["licences"]
    local availableLicenses = table_clone(Config.Cityhalls[closestCityhall].licenses)
    /*for license, data in pairs(availableLicenses) do
        if data.metadata and not licensesMeta[data.metadata] then
            availableLicenses[license] = nil
        end
    end*/
    cb(availableLicenses)
end)

RegisterNUICallback('applyJob', function(job, cb)
    if PlayerData.job.type == "leo" or PlayerData.job.type == "fire" then
      QBCore.Functions.Notify(Lang:t('error.job_check'), 'error')
    else
      if inRangeCityhall then
        TriggerServerEvent('qb-cityhall:server:ApplyJob', job, Config.Cityhalls[closestCityhall].coords)
      else
        QBCore.Functions.Notify(Lang:t('error.not_in_range'), 'error')
      end
    end
    cb('ok')
end)

-- Threads

CreateThread(function()
  while true do
    if isLoggedIn then
      playerPed = PlayerPedId()
      playerCoords = GetEntityCoords(playerPed)
      closestCityhall = getClosestHall()
    end
    Wait(1000)
  end
end)

CreateThread(function()
  initBlips()
  spawnPeds()
  QBCore.Functions.TriggerCallback('qb-cityhall:server:receiveJobs', function(result)
    SendNUIMessage({
      action = 'setJobs',
      jobs = result
    })
  end)
end)
