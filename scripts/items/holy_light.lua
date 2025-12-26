local game = Game()

return function(mod, utils)
    -- HOLY_LIGHT ID 안전하게 감지 (Holy Light ID: 374)
    local HOLY_LIGHT = Isaac.GetItemIdByName("Holy Light")
    if HOLY_LIGHT == -1 or not HOLY_LIGHT then HOLY_LIGHT = 374 end
    
    local V_CRACK    = EffectVariant.CRACK_THE_SKY

    local function hlDmgMult(count)
        return (count <= 0) and 1.0 or (3.0 * (1.2 ^ (count - 1)))
    end
    local function hlVisMult(count)
        return (count <= 0) and 1.0 or (1.0 + 0.03 * (count - 1))
    end

    local function hlEnsureBase(eff)
        local d = eff:GetData()
        if d.__hl_base_saved then return end
        d.__hl_base_saved = true
        d.__hl_base_scale = eff.SpriteScale or Vector(1,1)
        d.__hl_base_size  = eff.Size or 1
    end

    local VISUAL_R0    = 11.5
    local INNER_RATIO  = 0.85
    local MAX_RADIUS   = 120.0
    local MIN_RADIUS   = 6.0
    local PULSE_FRAMES = {1,2,3}
    local DMG_FLAGS    = (DamageFlag.DAMAGE_NO_PENALTIES or 0)

    local function hlFrameIn(tbl, f)
        for _, v in ipairs(tbl) do
            if v == f then return true end
        end
        return false
    end

    local function hlIsEnemy(ent)
        local npc = ent and ent:ToNPC()
        if not npc then return false end
        if not npc:IsVulnerableEnemy() then return false end
        if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return false end
        return true
    end

    local function hlApplyMainPillar(eff)
        hlEnsureBase(eff)
        local d = eff:GetData()

        local p = eff.SpawnerEntity and eff.SpawnerEntity:ToPlayer()
        if not p then
            local nearest, best = nil, 1e12
            for i = 0, game:GetNumPlayers() - 1 do
                local pl   = Isaac.GetPlayer(i)
                local dist = (pl.Position - eff.Position):LengthSquared()
                if dist < best then best, nearest = dist, pl end
            end
            p = nearest
        end
        local count = p and p:GetCollectibleNum(HOLY_LIGHT) or 0

        local sMul = hlVisMult(count)
        eff.SpriteScale = Vector(d.__hl_base_scale.X * sMul, d.__hl_base_scale.Y * sMul)

        if p then
            eff.CollisionDamage = p.Damage * hlDmgMult(count)
        end

        return p, count
    end

    local function hlApplyAoePulse(eff, player, count)
        if not player then return end
        local f = eff.FrameCount
        if not hlFrameIn(PULSE_FRAMES, f) then return end

        local d = eff:GetData()
        if d.__hl_pulse_tag ~= f then
            d.__hl_pulse_tag = f
            d.__hl_hit = {}
        end

        local baseS = d.__hl_base_scale.X ~= 0 and d.__hl_base_scale.X or 1
        local curS  = eff.SpriteScale.X
        local sVis  = curS / baseS
        local radius = math.max(MIN_RADIUS,
                        math.min(VISUAL_R0 * sVis * INNER_RATIO, MAX_RADIUS))

        local desiredDmg = player.Damage * hlDmgMult(count)
        local ents = Isaac.FindInRadius(eff.Position, radius, EntityPartition.ENEMY)

        for _, e in ipairs(ents) do
            if hlIsEnemy(e) then
                local id = utils.pHash(e)
                if not d.__hl_hit[id] then
                    e:TakeDamage(desiredDmg, DMG_FLAGS, EntityRef(player), 0)
                    d.__hl_hit[id] = true
                end
            end
        end
    end

    function mod:OnCrackInit(eff)
        if eff.Variant ~= V_CRACK then return end
        local p, count = hlApplyMainPillar(eff)
        hlApplyAoePulse(eff, p, count)
    end
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.OnCrackInit)

    function mod:OnCrackUpdate(eff)
        if eff.Variant ~= V_CRACK then return end
        local p, count = hlApplyMainPillar(eff)
        hlApplyAoePulse(eff, p, count)
    end
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnCrackUpdate)
end
