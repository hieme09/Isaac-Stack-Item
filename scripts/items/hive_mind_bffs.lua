return function(mod, utils)
    -- 아이템 ID 안전하게 감지 (Hive: 248, BFFS: 247)
    local HIVEMIND = Isaac.GetItemIdByName("Hive Mind")
    if HIVEMIND == -1 or not HIVEMIND then HIVEMIND = 248 end
    
    local BFFS = Isaac.GetItemIdByName("BFFS!")
    if BFFS == -1 or not BFFS then BFFS = 247 end

    local ADD_PER_STACK_BFF = 0.50

    local BLUE_FLY    = FamiliarVariant.BLUE_FLY
    local BLUE_SPIDER = FamiliarVariant.BLUE_SPIDER
    local INCUBUS     = FamiliarVariant.INCUBUS
    local SUCCUBUS    = FamiliarVariant.SUCCUBUS

    local function isFlyOrSpiderFam(fam)
        return fam and (fam.Variant == BLUE_FLY or fam.Variant == BLUE_SPIDER)
    end

    local function stackMultAdditive(stacks)
        if stacks <= 0 then return 1 end
        return 2 + ADD_PER_STACK_BFF * (stacks - 1)
    end

    local function bffStackMult(bff)
        return stackMultAdditive(bff)
    end

    local function bffExtraMultForEngineBuffed(fam)
        if not fam or isFlyOrSpiderFam(fam) then return 1 end
        local p = fam.Player
        if not p then return 1 end
        local bff = p:GetCollectibleNum(BFFS)
        if bff <= 0 then return 1 end
        return 1 + (ADD_PER_STACK_BFF * 0.5) * (bff - 1)
    end

    local function nearestIncubusForPlayer(posEntity, ownerPlayer, radiusPx)
        local pos = posEntity.Position
        local nearest, bestD2 = nil, (radiusPx * radiusPx)
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)) do
            local f = e:ToFamiliar()
            if f and f.Variant == INCUBUS and f.Player and ownerPlayer and f.Player.InitSeed == ownerPlayer.InitSeed then
                local d2 = (f.Position - pos):LengthSquared()
                if d2 < bestD2 then nearest, bestD2 = f, d2 end
            end
        end
        return nearest
    end

    local function incuFiredThisTear(tear, incu)
        if not (tear and incu) then return false end
        local v = tear.Velocity
        if not v or v:LengthSquared() < 1e-4 then return false end

        local dpos = tear.Position - incu.Position
        local dir  = v:Normalized()
        local t    = dpos:Dot(dir)
        if t <= -2 then return false end
        local perp = (dpos - dir * t):Length()
        return (dpos:LengthSquared() <= (48*48)) and (perp <= 10)
    end

    local function applyBffProjectileOnce(ent, mult, baseGetter, baseSetter, tag)
        if mult == 1 then return end
        local d = ent:GetData()
        if d[tag .. "_applied"] then return end

        d[tag .. "_applied"]      = true
        d[tag .. "_frames_left"]  = 2
        local base                = baseGetter(ent)
        d[tag .. "_base"]         = base
        d[tag .. "_mult"]         = mult
        baseSetter(ent, base * mult)
    end

    local function tickReassertProjectile(ent, baseGetter, baseSetter, tag)
        local d    = ent:GetData()
        local left = d[tag .. "_frames_left"]
        if not left or left <= 0 then return end

        local base = d[tag .. "_base"]
        local mult = d[tag .. "_mult"] or 1
        if base and mult ~= 1 then
            baseSetter(ent, base * mult)
        end
        d[tag .. "_frames_left"] = left - 1
    end

    function mod:OnFamiliarUpdate_HiveMindOnly(fam)
        local player = fam.Player
        if not player then return end

        local v = fam.Variant
        if v ~= BLUE_FLY and v ~= BLUE_SPIDER then return end

        local hive = player:GetCollectibleNum(HIVEMIND)
        if hive <= 0 then return end

        local d = fam:GetData()
        if not d.__hive_base_init then
            d.__hive_base_damage = fam.CollisionDamage
            d.__hive_base_scale  = fam.SpriteScale or Vector(1, 1)
            d.__hive_base_size   = fam.Size or 10
            d.__hive_base_init   = true
        end

        local dmg_mult = stackMultAdditive(hive)
        fam.CollisionDamage = (d.__hive_base_damage or fam.CollisionDamage) * dmg_mult

        if HM_SCALE_PER_STACK ~= 0 then
            local scale_mult = 1 + HM_SCALE_PER_STACK * (hive - 1)
            fam.SpriteScale  = Vector(
                d.__hive_base_scale.X * scale_mult,
                d.__hive_base_scale.Y * scale_mult
            )
            fam.Size         = (d.__hive_base_size or fam.Size) * scale_mult
        end
    end
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_HiveMindOnly)

    local function applyBffToFamiliarBody(fam)
        local player = fam.Player
        if not player or isFlyOrSpiderFam(fam) then return end

        local bff = player:GetCollectibleNum(BFFS)
        if bff <= 0 then return end

        local d = fam:GetData()
        if not d.__bff_base_init then
            d.__bff_base_damage = fam.CollisionDamage
            d.__bff_base_scale  = fam.SpriteScale or Vector(1,1)
            d.__bff_base_size   = fam.Size or 10
            d.__bff_base_init   = true
        end

        local dmg_mult   = bffStackMult(bff)
        local scale_mult = 1 + BFF_SCALE_PER_STACK * (bff - 1)

        fam.CollisionDamage = (d.__bff_base_damage or fam.CollisionDamage) * dmg_mult
        fam.SpriteScale     = Vector(d.__bff_base_scale.X * scale_mult, d.__bff_base_scale.Y * scale_mult)
        fam.Size            = (d.__bff_base_size or fam.Size) * scale_mult
    end

    function mod:OnFamiliarUpdate_BFF(fam)
        applyBffToFamiliarBody(fam)
    end
    mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_BFF)

    function mod:OnTearInit_BFF(tear)
        local td = tear:GetData()
        if td.__bff_any_applied then return end

        local fam = (tear.Parent and tear.Parent:ToFamiliar()) or (tear.SpawnerEntity and tear.SpawnerEntity:ToFamiliar())
        if fam then
            if isFlyOrSpiderFam(fam) then return end

            if fam.Variant == INCUBUS then
                td.__bff_incu_wait   = true
                td.__bff_incu_owner  = fam.Player and fam.Player.InitSeed or nil
                td.__bff_any_applied = true
                return
            else
                local mult = bffExtraMultForEngineBuffed(fam)
                applyBffProjectileOnce(
                    tear, mult,
                    function(t) return (t.CollisionDamage and t.CollisionDamage > 0) and t.CollisionDamage or 3.5 end,
                    function(t, v) t.CollisionDamage = v end,
                    "__bff_tear"
                )
                td.__bff_any_applied = true
                return
            end
        end

        local ownerP = (tear.Parent and tear.Parent:ToPlayer()) or (tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer())
        if ownerP then
            local incu = nearestIncubusForPlayer(tear, ownerP, 48)
            if incu and incuFiredThisTear(tear, incu) then
                td.__bff_incu_wait   = true
                td.__bff_incu_owner  = ownerP.InitSeed
                td.__bff_any_applied = true
            end
            return
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, mod.OnTearInit_BFF)

    function mod:OnTearUpdate_BFF(tear)
        local td = tear:GetData()

        if td.__bff_incu_wait and not td.__bff_incu_done then
            if tear.CollisionDamage and tear.CollisionDamage > 0 then
                local ownerP = Isaac.GetPlayer(0)
                if td.__bff_incu_owner and ownerP and ownerP.InitSeed ~= td.__bff_incu_owner then
                    -- TODO: 멀티플레이 대응
                end
                local incu = nearestIncubusForPlayer(tear, ownerP, 56)
                local mult = 1
                if incu then
                    mult = bffExtraMultForEngineBuffed(incu)
                end
                if mult ~= 1 then
                    applyBffProjectileOnce(
                        tear, mult,
                        function(t) return t.CollisionDamage end,
                        function(t, v) t.CollisionDamage = v end,
                        "__bff_tear"
                    )
                end
                td.__bff_incu_done = true
                td.__bff_incu_wait = false
            end
        end

        tickReassertProjectile(
            tear,
            function(t) return t.CollisionDamage end,
            function(t, v) t.CollisionDamage = v end,
            "__bff_tear"
        )
    end
    mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, mod.OnTearUpdate_BFF)

    function mod:OnLaserInit_BFF(laser)
        local ld = laser:GetData()
        if ld.__bff_lz_marked then return end
        ld.__bff_lz_marked = true
        ld.__bff_lz_done   = false
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, mod.OnLaserInit_BFF)

    function mod:OnLaserUpdate_BFF(laser)
        local ld = laser:GetData()
        if not ld.__bff_lz_marked or ld.__bff_lz_done then return end

        local fam = (laser.Parent and laser.Parent:ToFamiliar()) or (laser.SpawnerEntity and laser.SpawnerEntity:ToFamiliar())
        if not fam or isFlyOrSpiderFam(fam) then ld.__bff_lz_done = true; return end

        local mult = bffExtraMultForEngineBuffed(fam)
        if mult == 1 then ld.__bff_lz_done = true; return end

        if laser.CollisionDamage and laser.CollisionDamage > 0 then
            local base = laser.CollisionDamage
            laser.CollisionDamage = base * mult
            ld.__bff_lz_done = true
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_BFF)

    function mod:OnEntityTakeDamage_BFF(entity, amount, flags, source, countdown)
        if amount <= 0 then return end
        if not source or not source.Entity then return end

        local fam = source.Entity:ToFamiliar()
        if fam and fam.Variant == SUCCUBUS and fam.Player then
            local bff  = fam.Player:GetCollectibleNum(BFFS)
            local mult = bffStackMult(bff)
            if mult == 1 then return end

            local fd = fam:GetData()
            if fd.__bff_succ_guard then
                return
            end

            fd.__bff_succ_guard = true
            entity:TakeDamage(amount * mult, flags, source, countdown)
            fd.__bff_succ_guard = false
            return true
        end
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityTakeDamage_BFF)
end
