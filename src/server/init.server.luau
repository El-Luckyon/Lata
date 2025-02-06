--!strict

local Lata = require(game.ReplicatedStorage.Lata)
local Players = game:GetService("Players")

local InventoryData = Lata.New("Inventory3", {Sword = false, Bow = false, Shank = true, Chestplate = false, Helmet = false, Boot = true, Leggings = false})

Players.PlayerAdded:Connect(function(Player: Player)
   local UserId = tostring(Player.UserId)
   local PlayerInventoryData = InventoryData:Data(UserId)
   local PlayerHasSword = InventoryData:Find(PlayerInventoryData, "Sword")
   local PlayerHasShank = InventoryData:Find(UserId, "Shank")
   InventoryData:Set(UserId, true, "Sword")
   print(PlayerHasSword, PlayerHasShank)
end)

Players.PlayerRemoving:Connect(function(Player: Player)
    local UserId = tostring(Player.UserId)
    InventoryData:Del(UserId)
    print(InventoryData)
end)