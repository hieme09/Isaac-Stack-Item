return function(mod, utils)
    -- TECH5 ID 안전하게 감지 (Technology .5 ID: 244)
    local TECH5 = Isaac.GetItemIdByName("Technology .5")
    if TECH5 == -1 or not TECH5 then TECH5 = 244 end
    
    local TECH5_SPREAD_DEG = 5

    local function markExtraT5(l)    l:GetData().t5_extra   = true end
    local function isExtraT5(l)      return l:GetData().t5_extra   == true end
    local function handledT5(l)      return l:GetData().t5_handled == true end
    local function setHandledT5(l)   l:GetData().t5_handled = true end

    local EXCLUDE_VARIANTS_T5 = {
        [LaserVariant.LASER_BRIMSTONE or -1] = true,
        [LaserVariant.LASER_TECH2    or -1] = true,
        [LaserVariant.LIGHT_RING     or -1] = true,
    }

    local function looksLikeTech5(l)
        if not (l.SpawnerEntity and l.SpawnerEntity:ToPlayer()) then return false end
        local t = l.Timeout or 0
        if t <= 0 or t > 30 then return false end
        if EXCLUDE_VARIANTS_T5[l.Variant or -1] then return false end
        return true
    end

    local t5_origins, t5_extras = {}, {}

    function mod:OnLaserUpdate_Tech5(laser)
        if isExtraT5(laser) or handledT5(laser) then return end
        local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
        if not player or not player:HasCollectible(TECH5) then return end

        setHandledT5(laser)
        if not looksLikeTech5(laser) then return end

        local count = player:GetCollectibleNum(TECH5)
        local extra = count - 1
        if extra <= 0 then
            markExtraT5(laser)
            return
        end

        local baseVariant = laser.Variant
        local baseAngle   = laser.AngleDegrees or 0
        local baseTimeout = laser.Timeout or 12
        local baseDamage  = laser.CollisionDamage or player.Damage
        local baseMaxDist = laser.GetMaxDistance and laser:GetMaxDistance() or nil
        -- 발사 오프셋(렌더 위치)도 원본 레이저 기준으로 맞춤
        local basePosOffset = laser.PositionOffset
            or (player.GetLaserOffset and player:GetLaserOffset())
            or Vector(0, -30)

        local originHash = utils.pHash(laser)
        t5_origins[originHash] = laser
        markExtraT5(laser)

        local half = (extra - 1) * 0.5
        for i = 0, extra - 1 do
            local ang = baseAngle + ((i - half) * TECH5_SPREAD_DEG)
            local spawnPos = laser.Position
            -- utils.ShootAngleCompat(variant, pos, angle, timeout, owner)
            local new = utils.ShootAngleCompat(baseVariant, spawnPos, ang, baseTimeout, player)
            if new then
                new.Position        = spawnPos
                new.PositionOffset  = basePosOffset
                new.SpawnerEntity   = player
                new.Parent          = player
                new.CollisionDamage = baseDamage

                local dist = baseMaxDist
                if (not dist) or dist <= 0 then
                    dist = utils.RaycastMaxDistance(spawnPos, ang, 240)
                end
                if new.SetMaxDistance then new:SetMaxDistance(dist) end

                if laser.TearFlags then new.TearFlags = laser.TearFlags end
                if (new.GridCollisionClass ~= nil) and (laser.GridCollisionClass ~= nil) then
                    new.GridCollisionClass = laser.GridCollisionClass
                end

                new.Color       = laser.Color
                new.DepthOffset = laser.DepthOffset
                new:Update()

                local d = new:GetData()
                d.t5_extra, d.t5_handled, d.t5_followHash = true, true, originHash
                table.insert(t5_extras, new)
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_Tech5)

    function mod:OnPostUpdate_Tech5Snap()
        for i = #t5_extras, 1, -1 do
            local l = t5_extras[i]
            if (not l) or (not l:Exists()) then
                table.remove(t5_extras, i)
            else
                local hash   = l:GetData() and l:GetData().t5_followHash
                local origin = hash and t5_origins[hash] or nil
                if origin and origin:Exists() then
                    l.Position = origin.Position
                else
                    if hash then t5_origins[hash] = nil end
                end
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnPostUpdate_Tech5Snap)

    function mod:OnNewRoom_Tech5()
        t5_origins, t5_extras = {}, {}
    end
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Tech5)

    function mod:OnGameStart_Tech5()
        t5_origins, t5_extras = {}, {}
    end
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Tech5)
end
