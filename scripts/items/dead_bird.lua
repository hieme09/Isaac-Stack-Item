return function(mod, utils)
    -- DEAD_BIRD ID 안전하게 감지 (Dead Bird ID: 117)
    local DEAD_BIRD = Isaac.GetItemIdByName("Dead Bird")
    if DEAD_BIRD == -1 or not DEAD_BIRD then DEAD_BIRD = 117 end
    
    local spawn_dead_bird = {true, true, true, true, true, true, true, true}

    function mod:OnPlayerDamage_DeadBird(entity, amount, flags, source, countdown)
        if entity.Type ~= EntityType.ENTITY_PLAYER then return end
        local player = entity:ToPlayer()
        if not (player and player:HasCollectible(DEAD_BIRD)) then return end

        local extra = player:GetCollectibleNum(DEAD_BIRD) - 1
        if extra <= 0 then return end

        local idx = player.Index + 1
        if not spawn_dead_bird[idx] then return end

        for _ = 1, extra do
            Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.DEAD_BIRD, 0, player.Position, Vector.Zero, player)
        end
        spawn_dead_bird[idx] = false
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_DeadBird)

    function mod:OnNewRoom_DeadBird()
        spawn_dead_bird = {true, true, true, true, true, true, true, true}
    end
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_DeadBird)
end
