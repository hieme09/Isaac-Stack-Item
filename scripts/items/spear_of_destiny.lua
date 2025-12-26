local game = Game()

return function(mod, utils)
    -- SPEAR_OF_DESTINY ID 안전하게 감지 (Spear of Destiny ID: 400)
    local SPEAR_OF_DESTINY = Isaac.GetItemIdByName("Spear of Destiny")
    if SPEAR_OF_DESTINY == -1 or not SPEAR_OF_DESTINY then SPEAR_OF_DESTINY = 400 end
    
    local spearVariant, spearGuard = nil, false
    local spearHitCD = {}
    local ADD_PER_STACK_SPEAR = 0.10

    local SPEAR_XSCALE_PER_STACK      = 0.15
    local SPEAR_ADD_LEN_PER_STACK     = 12
    local SPEAR_TIP_BACK_PAD          = 6
    local SPEAR_BASE_HALF_WIDTH       = 10
    local SPEAR_EXTRA_WIDTH_PER_STACK = 2
    local SPEAR_COOLDOWN_FRAMES       = 3

    local function spear_total_mult(stacks)
        if stacks <= 1 then return 1 end
        return 1 + ADD_PER_STACK_SPEAR * (stacks - 1)
    end

    function mod:OnGameStart_Spear()
        spearVariant, spearGuard = nil, false
        spearHitCD = {}
    end
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Spear)

    function mod:OnNewRoom_Spear()
        spearHitCD = {}
    end
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Spear)

    function mod:OnEntityDamage_SpearOnly(entity, amount, flags, source, countdown)
        if spearGuard then return end
        if not (entity and entity:IsVulnerableEnemy()) then return end
        if not (source and source.Entity) then return end

        local src = source.Entity
        if src.Type ~= EntityType.ENTITY_EFFECT then return end
        local eff = src:ToEffect()
        if not eff then return end

        if not spearVariant then
            local owner = src.SpawnerEntity and src.SpawnerEntity:ToPlayer() or nil
            if owner and owner:HasCollectible(SPEAR_OF_DESTINY) then
                spearVariant = eff.Variant
            end
        end
        if spearVariant and eff.Variant ~= spearVariant then return end

        local player = src.SpawnerEntity and src.SpawnerEntity:ToPlayer() or nil
        if not player then return end

        local stacks = player:GetCollectibleNum(SPEAR_OF_DESTINY)
        if stacks <= 1 then return end

        local mult = spear_total_mult(stacks)

        spearGuard = true
        entity:TakeDamage((amount or 0) * mult, flags or 0, source, countdown or 0)
        spearGuard = false

        return false
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityDamage_SpearOnly)

    function mod:OnEffectUpdate_SpearLength(effect)
        if effect.Type ~= EntityType.ENTITY_EFFECT then return end
        local eff = effect:ToEffect()
        if not eff then return end

        local player = effect.SpawnerEntity and effect.SpawnerEntity:ToPlayer() or nil
        if not player then return end

        local stacks = player:GetCollectibleNum(SPEAR_OF_DESTINY)
        if stacks <= 1 then return end
        local extra = stacks - 1

        if not spearVariant then spearVariant = eff.Variant end
        if spearVariant and eff.Variant ~= spearVariant then return end

        if SPEAR_XSCALE_PER_STACK ~= 0 then
            effect.SpriteScale = Vector(
                1 + SPEAR_XSCALE_PER_STACK * extra,
                effect.SpriteScale.Y
            )
        end

        local dir = effect.Position - player.Position
        local dlen = dir:Length()
        if dlen < 0.1 then return end
        dir = dir / dlen

        local addLen = SPEAR_ADD_LEN_PER_STACK * extra
        if addLen <= 0 then return end

        local tipStart = effect.Position - dir * SPEAR_TIP_BACK_PAD
        local halfW    = SPEAR_BASE_HALF_WIDTH + (SPEAR_EXTRA_WIDTH_PER_STACK * extra)

        local dmgMult     = spear_total_mult(stacks)
        local spearDamage = (player.Damage or 0) * 2 * dmgMult

        local frame = game:GetFrameCount()
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:IsVulnerableEnemy() and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and not e:IsDead() then
                local rel = e.Position - tipStart
                local t   = rel:Dot(dir)
                if t >= 0 and t <= (SPEAR_TIP_BACK_PAD + addLen) then
                    local perp = rel - dir * t
                    if perp:Length() <= halfW then
                        local key = utils.pHash(e)
                        if (spearHitCD[key] or 0) <= frame then
                            spearHitCD[key] = frame + SPEAR_COOLDOWN_FRAMES
                            spearGuard = true
                            e:TakeDamage(spearDamage, 0, EntityRef(effect), 0)
                            spearGuard = false
                        end
                    end
                end
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnEffectUpdate_SpearLength)
end
