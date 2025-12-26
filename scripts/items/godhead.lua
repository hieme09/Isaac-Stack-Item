return function(mod, utils)
    -- GODHEAD ID 안전하게 감지 (Godhead ID: 331)
    local GODHEAD = Isaac.GetItemIdByName("Godhead")
    if GODHEAD == -1 or not GODHEAD then GODHEAD = 331 end
    
    local _godheadGuard = false

    function mod:OnEntityDamage_Godhead(entity, amount, flags, source, countdown)
        if _godheadGuard then return end
        if not (entity and entity:IsVulnerableEnemy()) then return end
        if not (source and source.Entity) then return end

        local tear = source.Entity:ToTear()
        if not tear then return end
        if (tear.TearFlags & TearFlags.TEAR_GLOW) == 0 then return end

        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if not player then return end

        local count = player:GetCollectibleNum(GODHEAD)
        if count <= 1 then return end

        local dmg = 2 + (count - 1) * 2
        _godheadGuard = true
        entity:TakeDamage(dmg, flags, source, countdown)
        _godheadGuard = false
        return false
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityDamage_Godhead)
end
