return function(mod, utils)
    -- 아이템 ID 안전하게 감지 (Choco: 69, MiP: 109)
    local CHOCOLATE_MILK = Isaac.GetItemIdByName("Chocolate Milk")
    if CHOCOLATE_MILK == -1 or not CHOCOLATE_MILK then CHOCOLATE_MILK = 69 end
    
    local MONEY_IS_POWER = Isaac.GetItemIdByName("Money = Power")
    if MONEY_IS_POWER == -1 or not MONEY_IS_POWER then MONEY_IS_POWER = 109 end

    function mod:OnEvaluateCache_All(player, cacheFlag)
        if cacheFlag ~= CacheFlag.CACHE_DAMAGE then return end

        local mip = player:GetCollectibleNum(MONEY_IS_POWER)
        if mip > 0 then
            player.Damage = player.Damage + (player:GetNumCoins() * 0.04 * mip)
        end

        local ch = player:GetCollectibleNum(CHOCOLATE_MILK)
        local d  = player:GetData()
        if ch > 0 then
            d.ChocoMin = 0.25 * ch
            d.ChocoMax = 2.0 + (ch - 1) * 1.0
        else
            d.ChocoMin, d.ChocoMax = nil, nil
        end
    end
    mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnEvaluateCache_All)

    function mod:OnTearInit_Choco(tear)
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if not player then return end
        if player:GetCollectibleNum(CHOCOLATE_MILK) <= 0 then return end

        local d       = player:GetData()
        local minMult = d.ChocoMin or 0.25
        local maxMult = d.ChocoMax or 2.0
        local charge  = math.min(1.0, tear.Charge or 1.0)

        tear.CollisionDamage = tear.CollisionDamage * (minMult + (maxMult - minMult) * charge)
    end
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTearInit_Choco)
end
