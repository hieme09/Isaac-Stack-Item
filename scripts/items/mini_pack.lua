local game = Game()

return function(mod, utils)
    -- MINIPACK ID 안전하게 감지 (Mini Pack ID: 711)
    local MINIPACK = Isaac.GetItemIdByName("Mini Pack")
    if MINIPACK == -1 then MINIPACK = 711 end 

    local ALLOWED_VARIANTS = {
        PickupVariant.PICKUP_COIN,
        PickupVariant.PICKUP_HEART,
        PickupVariant.PICKUP_KEY,
        PickupVariant.PICKUP_BOMB,
        PickupVariant.PICKUP_BATTERY
    }

    local function spawnAllowedPickup(rng, player)
        local room = game:GetRoom()
        local pos  = room:FindFreePickupSpawnPosition(player.Position, 0, true)
        local idx  = rng:RandomInt(#ALLOWED_VARIANTS) + 1
        local variant = ALLOWED_VARIANTS[idx]
        Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, 0, pos, Vector.Zero, player)
    end

    function mod:OnEntityTakeDamage_MiniPack(ent, amount, flags, source, countdown)
        local player = ent:ToPlayer()
        if not player or not player:HasCollectible(MINIPACK) then return end

        local count = player:GetCollectibleNum(MINIPACK)
        if count <= 0 then return end

        local rng = player:GetCollectibleRNG(MINIPACK)
        for _ = 1, count do
            if rng:RandomFloat() < 0.5 then
                spawnAllowedPickup(rng, player)
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityTakeDamage_MiniPack)
end
