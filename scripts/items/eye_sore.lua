local game = Game()
local api = StackItemAPI

return function(mod, utils)
    -- EYESORE ID 안전하게 감지
    local EYESORE = CollectibleType.COLLECTIBLE_EYE_SORE or Isaac.GetItemIdByName("Eye Sore")
    if EYESORE == -1 or not EYESORE then EYESORE = 710 end
    
    print("[Stackable Items] Eye Sore module loaded. ID: " .. tostring(EYESORE))

    local _inEyeSore = false

    -- Technology 2(보조 레이저) 예외 처리용
    local TECH2_ID = (CollectibleType and CollectibleType.COLLECTIBLE_TECHNOLOGY_2) or -1
    if (not TECH2_ID) or TECH2_ID <= 0 then
        -- 지역/버전/표기 차이를 고려해서 둘 다 시도
        TECH2_ID = Isaac.GetItemIdByName("Technology 2")
        if (not TECH2_ID) or TECH2_ID <= 0 then
            TECH2_ID = Isaac.GetItemIdByName("Tech 2")
        end
    end
    local LASER_TECH2 = (LaserVariant and LaserVariant.LASER_TECH2) or -1

    -- Technology 0(Tech Zero) 예외 처리용: Tech Zero는 체인/보조 레이저 성격이라 Eyesore “레이저 추가발사”가 어색함
    -- 대신 Eyesore는 Tear처럼 발사되게 한다(발동 감지는 레이저에서 하되, 발사 타입만 Tear로 강제)
    local TECH0_ID = (CollectibleType and CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO) or -1
    if (not TECH0_ID) or TECH0_ID <= 0 then
        TECH0_ID = Isaac.GetItemIdByName("Tech Zero")
        if (not TECH0_ID) or TECH0_ID <= 0 then
            TECH0_ID = Isaac.GetItemIdByName("Technology Zero")
        end
    end

    -- 플레이어 공격을 스탯 반영해서 복제 발사하는 통합 함수
    local function FireMimicAttack(player, angle, pType, sourceEntity)
        local pos = player.Position + (player.TearsOffset or Vector.Zero)
        local sSpeed = player.ShotSpeed or 1.0
        local damage = player.Damage
        local flags = player.TearFlags
        local pRange = player.Range or 400
        
        local wType = 1
        if player.GetWeaponType then wType = player:GetWeaponType() end

        -- sourceEntity가 레이저인 경우 레이저 속성(Variant/Timeout)을 가져오기
        local sourceLaser = sourceEntity and sourceEntity:ToLaser()
        local laserVariant = sourceLaser and sourceLaser.Variant or 1
        local laserTimeout = sourceLaser and sourceLaser.Timeout or 20

        -- Technology 2는 “연속 보조 레이저”라 Eye Sore가 레이저를 추가 발사하면 어색해짐
        -- 따라서 Tech2 보유 중이거나, 원본 레이저가 Tech2 변종이면 “눈물 기반”으로만 복제하도록 강제한다
        local hasTech2 = (TECH2_ID and TECH2_ID > 0) and player:HasCollectible(TECH2_ID)
        local isTech2Laser = (laserVariant == LASER_TECH2)
        local forceTearForTech2 = hasTech2 or isTech2Laser

        -- Tech Zero도 Eyesore는 Tear처럼 발사되게 강제
        local hasTech0 = (TECH0_ID and TECH0_ID > 0) and player:HasCollectible(TECH0_ID)
        local isTech0Laser = false
        if sourceLaser and sourceLaser.IsCircleLaser and sourceLaser:IsCircleLaser() then
            -- EntityLaser 문서: Circle Laser SubType 4 = No Impact (Tech Zero 등)
            isTech0Laser = (sourceLaser.SubType == 4)
        end
        local forceTearForTech0 = hasTech0 or isTech0Laser

        api:PrintDebug(string.format("FireMimic | pType:%s | wType:%d | srcVar:%s", 
            tostring(pType), wType, tostring(laserVariant)))

        local dirV = Vector.FromAngle(angle)
        
        -- 1) Tech X (WeaponType 9 / 원본 레이저가 Tech X 링일 때)
        -- Variant==2 같은 단순 판정은 다른 레이저를 오인식할 수 있어서, CircleLaser+SubType으로 확인
        local isTechXRing = false
        if sourceLaser and sourceLaser.IsCircleLaser and sourceLaser:IsCircleLaser() then
            -- EntityLaser 문서: Circle Laser SubType 2 = Tech X
            isTechXRing = (sourceLaser.SubType == 2)
        end

        if wType == 9 or isTechXRing then
            api:PrintDebug("Executing FireTechXLaser")
            local radius = sourceLaser and sourceLaser.Radius or 30
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
        
        -- 2) Brimstone / Tech 시너지 (WeaponType 2 또는 레이저 Variant 1/5/9/11)
        elseif wType == 2 
           or (sourceEntity and (sourceEntity.Variant == 1 or sourceEntity.Variant == 5 or sourceEntity.Variant == 9 or sourceEntity.Variant == 11))
           or (wType == 3 and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)) then
            
            api:PrintDebug("Executing FireBrimstone (Synergy Check)")
            local l = player:FireBrimstone(dirV, player, 1.0)
            if l then
                -- EntityLaser 속성(문서 기준) 세팅
                l.TearFlags = flags
                l.CollisionDamage = damage
                if player.LaserColor then l.Color = player.LaserColor end
                
                local ld = l:GetData()
                ld.__is_eyesore_extra = true
                ld.__parent_laser = sourceEntity
                l.Timeout = laserTimeout

                if sourceLaser then
                    ld.__initial_parent_angle = sourceLaser.Angle
                    ld.__initial_mimic_angle = l.Angle
                end
            end

        -- 3) Technology (WeaponType 3)
        -- Tech2/Tech0는 레이저 복제 금지(눈물로만 처리)
        elseif (wType == 3 or pType == "laser") and (not forceTearForTech2) and (not forceTearForTech0) then
            api:PrintDebug("Executing FireTechLaser")
            local l = player:FireTechLaser(pos, 0, dirV, true, true, player, 1.0)
            if l then
                l.TearFlags = flags
                l.CollisionDamage = damage
                if player.LaserColor then l.Color = player.LaserColor end
                l.OneHit = true
                l:GetData().__is_eyesore_extra = true

                -- 원본 레이저의 지속시간을 따라가게 (Technology가 “안 나가는 것처럼” 보이는 현상 방지)
                if sourceLaser and sourceLaser.Timeout then
                    l.Timeout = sourceLaser.Timeout
                end
            end

        -- 4) Mom's Knife
        elseif wType == 4 or pType == "knife" then
            api:PrintDebug("Executing FireKnife")
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

        elseif wType == 5 or pType == "bomb" then
            api:PrintDebug("Executing FireBomb")
            local b = player:FireBomb(pos, dirV:Resized(sSpeed * 10), player)
            if b then
                b.CollisionDamage = damage
                if b.ToBomb then b:ToBomb().IsFetus = true end
                b:GetData().__is_eyesore_extra = true
            end

        -- 6) 기본: Tears
        else
            api:PrintDebug("Executing FireTear")
            -- 원본 tear의 실제 속성을 최대한 복사해서(데미지/플래그/차지 등) 시너지/스택이 그대로 반영되게 한다
            local srcTear = sourceEntity and sourceEntity:ToTear() or nil
            local t = player:FireTear(pos, dirV:Resized(sSpeed * 10), false, false, false)
            if t then
                -- Eyesore로 생성한 추가 눈물은 다시 Eyesore 트리거가 되지 않게 마킹
                local td = t:GetData()
                td.__is_eyesore_extra = true

                -- “통째 복사” 대신 utils 헬퍼로 주요 속성을 일괄 복사
                utils.CopyTear(srcTear, t, damage, flags)

                -- [DEBUG] 복사 확인용
                if srcTear then
                    api:PrintDebug(string.format(
                        "TearCopy | srcDmg:%s srcFlags:%s srcCharge:%s srcVar:%s",
                        tostring(srcTear.CollisionDamage),
                        tostring(srcTear.TearFlags),
                        tostring(srcTear.Charge),
                        tostring(srcTear.Variant)
                    ))
                end
            end
        end
    end

    -- Eye Sore 발동(추가 발사) 로직
    local function TryProcEyeSore(player, pType, sourceEntity)
        if _inEyeSore then return end
        if not (player and player:Exists()) then return end

        local count = player:GetCollectibleNum(EYESORE)
        if count < 1 then return end 

        local rng = player:GetCollectibleRNG(EYESORE)
        local extraShots = (count - 1) * 2 + rng:RandomInt(3)

        _inEyeSore = true

        for _ = 1, extraShots do
            local angle = rng:RandomFloat() * 360.0
            FireMimicAttack(player, angle, pType, sourceEntity)
        end

        _inEyeSore = false
    end

    -- 콜백들
    function mod:OnTear_EyeSore(tear)
        if _inEyeSore then return end
        -- Eyesore로 생성된 추가 눈물은 트리거에서 제외 (무한 발사 방지)
        local td = tear:GetData()
        if td and td.__is_eyesore_extra then
            return
        end
        local player = utils.ResolveOwnerPlayer(tear)
        if not player then return end

        -- Tech 2는 차징 시작/종료 모두에서 tear 이벤트가 잡히는 케이스가 있음.
        -- "차징 시작" 더미 tear는 막고, "차징 완료 후 발사"만 통과시키기 위해 Charge 기준으로 필터링한다.
        if TECH2_ID and TECH2_ID > 0 and player:HasCollectible(TECH2_ID) then
            local charge = tear.Charge

            -- Charge 정보가 있으면: 거의/완전 충전 발사만 허용
            if charge ~= nil then
                local TECH2_RELEASE_CHARGE_MIN = 0.95
                if charge < TECH2_RELEASE_CHARGE_MIN then
                    return
                end
            end

            -- [DEBUG] Tech2 차지 관련 상태 확인
            api:PrintDebug(string.format(
                "Tech2 TearGate | charge:%s wait:%s vel2:%s",
                tostring(charge),
                tostring(tear.WaitFrames),
                tostring((tear.Velocity and tear.Velocity:LengthSquared()) or 0)
            ))
        end

        TryProcEyeSore(player, "tear", tear)
    end
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTear_EyeSore)

    function mod:OnLaserUpdate_EyeSore(laser)
        local player = utils.ResolveOwnerPlayer(laser)
        if not player then return end
        local ld = laser:GetData()

        -- Tech.5(Technology .5) 보조 레이저는 Eye Sore 트리거로 취급하지 않음
        -- (보조 레이저가 다시 Eye Sore를 불러서 Tech X 링처럼 퍼지는 현상 방지)
        if ld.t5_extra or ld.t5_handled then
            return
        end

        -- Tech Zero는 기본 공격이 눈물이고, 레이저는 "체인/보조"로 계속 생성될 수 있음.
        -- 따라서 Tech Zero 보유 중에는 레이저 업데이트를 Eyesore 트리거로 쓰지 않는다 (tear 콜백만 사용).
        if (not ld.__is_eyesore_extra) and TECH0_ID and TECH0_ID > 0 and player:HasCollectible(TECH0_ID) then
            return
        end

        -- Technology 2의 보조 레이저(연속 레이저)는 Eye Sore 트리거로 취급하지 않음
        -- (Tech2는 “레이저로 Eyesore를 발사”하면 안됨)
        if laser.Variant == LASER_TECH2 and (not ld.__is_eyesore_extra) then
            return
        end

        -- Technology 0(Tech Zero) 체인/보조 레이저는 Eyesore 트리거로 취급하지 않음
        -- Tech Zero는 기본 공격이 "눈물"이므로, Eyesore는 MC_POST_FIRE_TEAR(원본 눈물)에서만 발동시키는 게 안전함
        if laser.IsCircleLaser and laser:IsCircleLaser() and laser.SubType == 4 and (not ld.__is_eyesore_extra) then
            return
        end

        -- 레이저 발동은 “안정적으로 동작하던 방식” 기준으로 유지 (혈사포 지속/소멸이 잘리지 않게)
        if not ld.__eyesore_proced and not ld.__is_eyesore_extra and not _inEyeSore then
            ld.__eyesore_proced = true
            TryProcEyeSore(player, "laser", laser)
        end
        
        if ld.__is_eyesore_extra then
            laser.PositionOffset = Vector(0, -30)
            
            -- 부모 레이저가 있으면 Timeout/회전을 동기화
            if ld.__parent_laser then
                if ld.__parent_laser:Exists() then
                    local pLaser = ld.__parent_laser:ToLaser()
                    if pLaser then
                        -- 부모 Timeout 그대로 따라가기
                        laser.Timeout = pLaser.Timeout

                        -- 회전 동기화 (Soy Milk 등 “움직이는 혈사포” 대응)
                        if ld.__initial_parent_angle and ld.__initial_mimic_angle then
                            local angleDelta = pLaser.Angle - ld.__initial_parent_angle
                            laser.Angle = ld.__initial_mimic_angle + angleDelta
                        end
                    end
                else
                    -- 부모 레이저가 완전히 사라진 경우만 제거(잔상 방지)
                    laser:Remove()
                    return
                end
            end
            
            -- 움직이는 레이저(Tech X 링 등)가 아니면 플레이어 위치에 고정
            if not ld.__is_moving_laser and laser.Variant ~= 2 then
                laser.Position = player.Position
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_EyeSore)

    function mod:OnBombInit_EyeSore(bomb)
        local player = utils.ResolveOwnerPlayer(bomb)
        if not player then return end
        
        local bd = bomb:GetData()
        if bd.__is_eyesore_extra then return end -- Don't re-proc from our own extra bombs

        local pWeapon = 1
        if player.GetWeaponType then pWeapon = player:GetWeaponType() end
        
        -- Dr. Fetus 감지:
        -- 문서상 WeaponType.WEAPON_BOMBS = 5 이지만, 일부 상황에서 GetWeaponType()이 1로 찍히는 경우가 있어서
        -- Dr. Fetus 소지 여부(collectible)로 보조 판정
        local hasDrFetus = player.HasCollectible and player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) or false

        -- “발사된 폭탄”만 인식:
        -- 설치 폭탄은 속도가 0에 가깝지만 완전 0이 아닐 수 있어서, ShotSpeed 기반 임계값으로 구분
        local vel2 = bomb.Velocity:LengthSquared()
        local shotSpeed = player.ShotSpeed or 1.0
        local minFiredVel = shotSpeed * 5
        local minFiredVel2 = minFiredVel * minFiredVel

        local isActuallyFired = (vel2 > minFiredVel2) and (pWeapon == 5 or hasDrFetus)

        -- [DEBUG] Dr. Fetus 판정 디버그
        api:PrintDebug(string.format(
            "BombInit | weapon:%s | hasDrFetus:%s | vel2:%s | minVel2:%s | frame:%s",
            tostring(pWeapon),
            tostring(hasDrFetus),
            tostring(vel2),
            tostring(minFiredVel2),
            tostring(bomb.FrameCount)
        ))
        
        if isActuallyFired and not bd.__eyesore_proced and not _inEyeSore then
            bd.__eyesore_proced = true
            TryProcEyeSore(player, "bomb", bomb)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, mod.OnBombInit_EyeSore)

    function mod:OnKnifeUpdate_EyeSore(knife)
        local player = utils.ResolveOwnerPlayer(knife)
        if not player then return end
        
        local kd = knife:GetData()
        
        -- 엔진 로직은 그대로 두고, extra knife만 정리(제거)한다
        if kd.__is_eyesore_extra then
            if not knife:IsFlying() then
                knife:Remove()
                return
            end
            return
        end

        -- 메인 칼(원본)에서만 발동
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
