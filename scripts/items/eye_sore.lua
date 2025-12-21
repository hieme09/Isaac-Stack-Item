local game = Game()

return function(mod, utils)
    -- Safe detection of EYESORE ID
    local EYESORE = CollectibleType.COLLECTIBLE_EYE_SORE or Isaac.GetItemIdByName("Eye Sore")
    if EYESORE == -1 or not EYESORE then EYESORE = 710 end
    
    print("[Stackable Items] Eye Sore module loaded. ID: " .. tostring(EYESORE))

    local _inEyeSore = false

    -- Unified function to mimic player attacks with Full Stat Reflection
    local function FireMimicAttack(player, angle, pType, sourceEntity)
        local pos = player.Position
        local sSpeed = player.ShotSpeed or 1.0
        local damage = player.Damage
        local flags = player.TearFlags
        local pRange = player.Range or 400
        
        local wType = 1
        if player.GetWeaponType then wType = player:GetWeaponType() end

        -- [DEBUG] Detailed tracking to log.txt
        local seType = sourceEntity and sourceEntity.Type or "N/A"
        local seVar = sourceEntity and sourceEntity.Variant or "N/A"
        Isaac.DebugString(string.format("[EyeSore] FireMimic | pType:%s | wType:%d | srcType:%s | srcVar:%s", 
            tostring(pType), wType, tostring(seType), tostring(seVar)))

        local dirV = Vector.FromAngle(angle)
        
        -- Get actual timeout from source laser if available
        local sourceLaser = sourceEntity and sourceEntity:ToLaser()
        local laserTimeout = sourceLaser and sourceLaser.Timeout or 20

        -- 1. Tech X (WeaponType 9)
        if wType == 9 then
            Isaac.DebugString("[EyeSore] Executing FireTechXLaser")
            local radius = (sourceEntity and sourceEntity:ToLaser()) and sourceEntity:ToLaser().Radius or 30
            local vel = dirV:Resized(sSpeed * 10)
            local l = player:FireTechXLaser(pos, vel, radius, player, 1.0)
            if l then
                l.TearFlags = flags
                l.CollisionDamage = damage
                if player.LaserColor then l.Color = player.LaserColor end
                local ld = l:GetData()
                ld.__is_eyesore_extra = true
                ld.__is_moving_laser = true
                l.MaxDistance = pRange
            end

        -- 2. Brimstone (WeaponType 2 OR Variant 1/9/11) - FIXED AS PER DOCS
        elseif wType == 2 or (sourceEntity and (sourceEntity.Variant == 1 or sourceEntity.Variant == 9 or sourceEntity.Variant == 11)) then
            Isaac.DebugString("[EyeSore] Executing FireBrimstone")
            -- EntityLaser FireBrimstone ( Vector Direction, Entity Spawner, float DamageMultiplier = 1.0 )
            local l = player:FireBrimstone(dirV, player, 1.0)
            if l then
                l.TearFlags = flags
                l.CollisionDamage = damage
                if player.LaserColor then l.Color = player.LaserColor end
                local ld = l:GetData()
                ld.__is_eyesore_extra = true
                ld.__parent_laser = sourceEntity -- Link for sync
                l.Timeout = laserTimeout

                -- Store initial angles for rotation sync
                if sourceEntity and sourceEntity:ToLaser() then
                    ld.__initial_parent_angle = sourceEntity:ToLaser().Angle
                    ld.__initial_mimic_angle = l.Angle
                end
            end

        -- 3. Technology / Regular Lasers (WeaponType 3)
        elseif wType == 3 or pType == "laser" then
            Isaac.DebugString("[EyeSore] Executing FireTechLaser")
            local l = player:FireTechLaser(pos, 0, dirV, true, true, player, 1.0)
            if l then
                l.TearFlags = flags
                l.CollisionDamage = damage
                if player.LaserColor then l.Color = player.LaserColor end
                l.OneHit = true
                l:GetData().__is_eyesore_extra = true
            end

        -- 4. Mom's Knife (Restored to User's Working Version)
        elseif wType == 4 or pType == "knife" then
            Isaac.DebugString("[EyeSore] Executing FireKnife")
            local v = (sourceEntity and sourceEntity.Variant) or 0
            local s = (sourceEntity and sourceEntity.SubType) or 0
            local knifeObj = sourceEntity and sourceEntity:ToKnife()
            local charge = knifeObj and knifeObj.Charge or 1.0
            
            local k_ent = player:FireKnife(player, angle, false, v, s)
            local k = k_ent and k_ent:ToKnife()
            if k then
                k.CollisionDamage = damage * 2
                k.TearFlags = flags
                if sourceEntity and sourceEntity.Color then k.Color = sourceEntity.Color end
                
                if k.SetPathFollowSpeed then 
                    k:SetPathFollowSpeed(0.12 * sSpeed) 
                end
                
                local kd = k:GetData()
                kd.__is_eyesore_extra = true
                kd.__eyesore_spawn_frame = game:GetFrameCount()
                
                if k.Shoot then 
                    local finalRange = pRange * 0.38 * sSpeed
                    k:Shoot(charge, finalRange) 
                end
            end

        -- 5. Dr. Fetus (Bombs)
        elseif wType == 5 or pType == "bomb" then
            Isaac.DebugString("[EyeSore] Executing FireBomb")
            local b = player:FireBomb(pos, dirV:Resized(sSpeed * 10))
            if b then
                b.CollisionDamage = damage
                b.TearFlags = flags
                b:GetData().__is_eyesore_extra = true
            end

        -- 6. Default: Tears
        else
            Isaac.DebugString("[EyeSore] Executing FireTear")
            local t = player:FireTear(pos, dirV:Resized(sSpeed * 10), false, false, false)
            if t then
                t.CollisionDamage = damage
                t.TearFlags = flags
                if sourceEntity and sourceEntity.Variant and sourceEntity.Variant > 0 then 
                    t:ChangeVariant(sourceEntity.Variant) 
                end
            end
        end
    end

    -- Eye Sore proc logic
    local function TryProcEyeSore(player, pType, sourceEntity)
        if _inEyeSore then return end
        if not (player and player:Exists()) then return end

        local count = player:GetCollectibleNum(EYESORE)
        if count <= 1 then return end

        local frame = game:GetFrameCount()
        local d     = player:GetData()
        
        -- Prevent multi-proc in the same frame
        d.__eyesore_last_fire_frame = d.__eyesore_last_fire_frame or -1
        if d.__eyesore_last_fire_frame == frame then return end
        
        local rng = player:GetCollectibleRNG(EYESORE)
        local extraShots = (count - 1) * 2 + rng:RandomInt(3)

        d.__eyesore_last_fire_frame = frame
        _inEyeSore = true

        for _ = 1, extraShots do
            local angle = rng:RandomFloat() * 360.0
            FireMimicAttack(player, angle, pType, sourceEntity)
        end

        _inEyeSore = false
    end

    -- Callbacks
    function mod:OnTear_EyeSore(tear)
        if _inEyeSore then return end
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if player then TryProcEyeSore(player, "tear", tear) end
    end
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTear_EyeSore)

    function mod:OnLaserUpdate_EyeSore(laser)
        local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
        if not player then return end
        local ld = laser:GetData()

        if not ld.__eyesore_proced and not ld.__is_eyesore_extra and not _inEyeSore then
            ld.__eyesore_proced = true
            TryProcEyeSore(player, "laser", laser)
        end
        
        if ld.__is_eyesore_extra then
            laser.PositionOffset = Vector(0, -30)
            
            -- Sync timeout with parent laser if it exists
            if ld.__parent_laser and ld.__parent_laser:Exists() then
                local pLaser = ld.__parent_laser:ToLaser()
                if pLaser then
                    -- While parent exists, keep syncing timeout to support items like Soy Milk
                    laser.Timeout = pLaser.Timeout

                    -- Sync rotation (Soy Milk / Moving Brimstone support)
                    if ld.__initial_parent_angle and ld.__initial_mimic_angle then
                        local angleDelta = pLaser.Angle - ld.__initial_parent_angle
                        laser.Angle = ld.__initial_mimic_angle + angleDelta
                    end
                end
            end
            
            -- Keep laser at player position if it's not a moving laser (like Tech X)
            if not ld.__is_moving_laser and laser.Variant ~= 2 then
                laser.Position = player.Position
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_EyeSore)

    function mod:OnBombInit_EyeSore(bomb)
        local player = bomb.SpawnerEntity and bomb.SpawnerEntity:ToPlayer()
        if not player then return end
        local pWeapon = 1
        if player.GetWeaponType then pWeapon = player:GetWeaponType() end
        if not (bomb.IsFetus or pWeapon == 5) then return end

        local bd = bomb:GetData()
        if not bd.__eyesore_proced and not bd.__is_eyesore_extra and not _inEyeSore then
            bd.__eyesore_proced = true
            TryProcEyeSore(player, "bomb", bomb)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, mod.OnBombInit_EyeSore)

    function mod:OnKnifeUpdate_EyeSore(knife)
        local player = knife.SpawnerEntity and knife.SpawnerEntity:ToPlayer()
        if not player then return end
        
        local kd = knife:GetData()
        
        -- Clean Engine Logic: Let the engine do the work, we just do the removing.
        if kd.__is_eyesore_extra then
            if not knife:IsFlying() then
                knife:Remove()
                return
            end
            return
        end

        -- Main Knife trigger
        if knife.Variant ~= 0 then return end
        if kd.__is_eyesore_extra then return end

        local isFlying = knife:IsFlying()
        if isFlying and not kd.__eyesore_launched and not _inEyeSore then
            kd.__eyesore_launched = true
            TryProcEyeSore(player, "knife", knife)
        elseif not isFlying then
            kd.__eyesore_launched = false
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, mod.OnKnifeUpdate_EyeSore)
end
