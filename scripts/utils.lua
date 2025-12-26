local game = Game()
local itemConfig = Isaac.GetItemConfig()

local utils = {}

-- =========================================================
-- 공통 유틸
-- =========================================================
function utils.pHash(e)
    if GetPtrHash then
        return GetPtrHash(e)
    end
    return tostring(e)
end

-- Laser ShootAngle 호환 래퍼
function utils.ShootAngleCompat(variant, pos, angle, timeout, owner)
    -- Repentance 기본 시그니처: (Variant, Position, Angle, Timeout, Spawner)
    local ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner)
    if ok and laser then 
        laser.Position = pos
        return laser 
    end

    -- 폴백 1: (Variant, Angle, Timeout, Position, Spawner)
    ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner)
    if ok and laser then 
        laser.Position = pos
        return laser 
    end

    -- 폴백 2: API 호출이 실패하면 수동 스폰
    local ent = Isaac.Spawn(EntityType.ENTITY_LASER, variant, 0, pos, Vector.Zero, owner)
    local l = ent:ToLaser()
    if l then
        l.AngleDegrees  = angle
        l.Timeout       = timeout
        l.SpawnerEntity = owner
        l.Parent        = owner
        return l
    end
    return nil
end

-- 방 안에서 Raycast 기반 최대 거리 추정
function utils.RaycastMaxDistance(pos, deg, fallback)
    local room = game:GetRoom()
    local FAR  = 2000
    local dir  = Vector.FromAngle(deg):Resized(FAR)

    local rc = room.Raycast or room.RayCast
    if rc then
        local ok, hit = pcall(function() return rc(room, pos, dir, 0, nil, false, false) end)
        if ok and hit and hit.X then
            return pos:Distance(hit)
        end
        ok, hit = pcall(function() return rc(room, pos, dir, 0, nil) end)
        if ok and hit and hit.X then
            return pos:Distance(hit)
        end
    end

    if room.CheckLine then
        local low, high = 0, FAR
        for _ = 1, 12 do
            local mid    = (low + high) * 0.5
            local target = pos + dir:Resized(mid)
            local clear  = false
            local ok, res = pcall(function() return room:CheckLine(pos, target, 0, 0, false, false) end)
            if ok and res then clear = true end
            if clear then low = mid else high = mid end
        end
        return math.max(24, high - 2)
    end

    return fallback or 240
end

-- 액티브 충전 유틸 (Rep+ / 구버전 호환)
function utils.AddActiveChargeCompat(player, amount, slot)
    if not player or amount == 0 then return end
    slot = slot or ActiveSlot.SLOT_PRIMARY

    if player.AddActiveCharge then
        player:AddActiveCharge(amount, slot)
        return
    end

    local activeItem = player:GetActiveItem(slot)
    if activeItem == 0 then return end

    local cfg        = itemConfig:GetCollectible(activeItem)
    local maxCharges = (cfg and cfg.MaxCharges) or 6

    local main    = player:GetActiveCharge(slot)
    local battery = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0

    local total = main + battery + amount
    if total < 0 then total = 0 end
    if total > maxCharges * 2 then
        total = maxCharges * 2
    end

    local newMain    = math.min(total, maxCharges)
    local newBattery = math.max(0, total - newMain)

    player:SetActiveCharge(newMain, slot)
    if player.SetBatteryCharge then
        player:SetBatteryCharge(newBattery, slot)
    end
end

-- tear 속성 복사용 헬퍼 (API에 "통째 복사"가 없어서 유틸로 제공)
-- srcTear: EntityTear, dstTear: EntityTear
-- fallbackDamage/flags: 원본을 못 읽거나 일부 값이 비어있을 때 사용할 플레이어 기반 값
function utils.CopyTear(srcTear, dstTear, fallbackDamage, fallbackFlags)
    if not dstTear then return end

    -- 원본 tear가 없으면 플레이어 스탯 기반으로만 세팅
    if not srcTear then
        if fallbackDamage ~= nil then dstTear.CollisionDamage = fallbackDamage end
        if fallbackFlags ~= nil then dstTear.TearFlags = fallbackFlags end
        return
    end

    -- 데미지 (Chocolate Milk 등 차지 반영된 값 포함)
    if srcTear.CollisionDamage and srcTear.CollisionDamage > 0 then
        dstTear.CollisionDamage = srcTear.CollisionDamage
    elseif fallbackDamage ~= nil then
        dstTear.CollisionDamage = fallbackDamage
    end

    -- 플래그 (Godhead 글로우 등 tear 단위 플래그 포함)
    if srcTear.TearFlags ~= nil then
        dstTear.TearFlags = srcTear.TearFlags
    elseif fallbackFlags ~= nil then
        dstTear.TearFlags = fallbackFlags
    end

    -- 기타 tear 단위 속성들
    if srcTear.Charge ~= nil then dstTear.Charge = srcTear.Charge end
    if srcTear.Color ~= nil then dstTear.Color = srcTear.Color end
    if srcTear.Scale ~= nil then dstTear.Scale = srcTear.Scale end
    if srcTear.FallingSpeed ~= nil then dstTear.FallingSpeed = srcTear.FallingSpeed end
    if srcTear.FallingAcceleration ~= nil then dstTear.FallingAcceleration = srcTear.FallingAcceleration end

    -- Variant는 EntityTear 문서처럼 ChangeVariant로 변경
    if srcTear.Variant and srcTear.Variant > 0 and dstTear.ChangeVariant then
        dstTear:ChangeVariant(srcTear.Variant)
    end
end

-- 멀티(코옵) 대응: 엔티티(tear/laser/bomb/knife 등)에서 "주인 플레이어"를 최대한 안정적으로 찾는다
-- 우선순위: SpawnerEntity(Player) > SpawnerEntity(Familiar.Player) > Parent(Player) > Parent(Familiar.Player)
function utils.ResolveOwnerPlayer(ent)
    if not ent then return nil end
    if ent.Exists and (not ent:Exists()) then return nil end

    local function playerFromEntity(e)
        if not e then return nil end
        if e.ToPlayer then
            local p = e:ToPlayer()
            if p then return p end
        end
        if e.ToFamiliar then
            local f = e:ToFamiliar()
            if f and f.Player then return f.Player end
        end
        return nil
    end

    -- SpawnerEntity 기반
    local sp = ent.SpawnerEntity
    local p = playerFromEntity(sp)
    if p then return p end

    -- Parent 기반
    local parent = ent.Parent
    p = playerFromEntity(parent)
    if p then return p end

    return nil
end

return utils
