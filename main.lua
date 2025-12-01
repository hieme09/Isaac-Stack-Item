-- =========================================================
-- Stackable Items RepPlus — Stabilized
-- =========================================================
local mod = RegisterMod("Stackable Items RepPlus", 1)
local game = Game()

-- =====================================================================
-- Active Charge Helper (Rep+ / 구버전 호환)
-- =====================================================================
local function AddActiveChargeCompat(player, amount, slot)
    if not player or amount == 0 then return end
    slot = slot or ActiveSlot.SLOT_PRIMARY

    -- Repentance API에 AddActiveCharge가 있으면 그대로 사용
    if player.AddActiveCharge then
        player:AddActiveCharge(amount, slot)
        return
    end

    -- 구버전 수동 구현
    local activeItem = player:GetActiveItem(slot)
    if activeItem == 0 then return end

    local cfg        = Isaac.GetItemConfig():GetCollectible(activeItem)
    local maxCharges = (cfg and cfg.MaxCharges) or 6

    local main    = player:GetActiveCharge(slot)
    local battery = 0
    if player.GetBatteryCharge then
        battery = player:GetBatteryCharge(slot)
    end

    local total = main + battery + amount
    if total < 0 then total = 0 end
    if total > maxCharges * 2 then
        total = maxCharges * 2 -- 메인+배터리 풀 오버차지
    end

    local newMain    = math.min(total, maxCharges)
    local newBattery = math.max(0, total - newMain)

    player:SetActiveCharge(newMain, slot)
    if player.SetBatteryCharge then
        player:SetBatteryCharge(newBattery, slot)
    end
end

-- =================================================================================================================================================================================================================================================
-- Habit (ID 156) — Nun's Habit: Battery 포함 오버차지까지 총량 보정
--  - 의도: "피격 전 메인+배터리 총량 + 수녀복이 줘야 하는 총 충전량" 을
--    무조건 만족시키도록 맞춰 줌.
--    Battery가 있으면 초과분이 자동으로 노란 오버차지 칸에 들어감.
-- =================================================================================================================================================================================================================================================
local HABIT = 156

mod.extraCharge = nil

-- 피격 직전에 "메인+배터리 총량"을 저장
function mod:OnPlayerDamage_Habit(entity, amount, flags, source, countdown)
    if entity.Type ~= EntityType.ENTITY_PLAYER then return end
    local player = entity:ToPlayer()
    local count  = player:GetCollectibleNum(HABIT)
    if count <= 0 then return end

    -- 어느 슬롯을 충전할지 선택
    local slot
    if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= 0 then
        slot = ActiveSlot.SLOT_PRIMARY
    elseif player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) ~= 0 then
        slot = ActiveSlot.SLOT_SECONDARY
    else
        return
    end

    local main0 = player:GetActiveCharge(slot)
    local bat0  = (player.GetBatteryCharge and player:GetBatteryCharge(slot)) or 0

    mod.extraCharge = {
        index  = player.ControllerIndex, -- 단일 플레이 기준
        slot   = slot,
        stacks = count,
        main0  = main0,
        bat0   = bat0,
    }
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_Habit)

-- 피격 처리 이후 프레임에서 "최종 충전량"을 강제로 맞춰 줌
function mod:OnUpdate_Habit()
    local ec = mod.extraCharge
    if not ec then return end
    mod.extraCharge = nil

    local player = Isaac.GetPlayer(ec.index)
    if not (player and player:Exists()) then return end

    local slot   = ec.slot
    local stacks = ec.stacks

    local activeItem = player:GetActiveItem(slot)
    if activeItem == 0 then return end

    local cfg        = Isaac.GetItemConfig():GetCollectible(activeItem)
    local maxCharges = (cfg and cfg.MaxCharges) or 6
    local maxTotal   = maxCharges * 2      -- The Battery 오버차지 포함 최대

    -- 수녀복 n개면 피격당 "총 +칸수" = 1(기본) + (n-1)
    local extraStacks = math.max(0, stacks - 1)
    local desiredGain = 1 + extraStacks

    -- 피격 후 현재 총량
    local main1  = player:GetActiveCharge(slot)
    local bat1   = (player.GetBatteryCharge and player:GetBatteryCharge(slot)) or 0
    local total1 = main1 + bat1

    -- 우리가 원하는 "최종 총량" = (피격 전 총량) + (수녀복이 줘야 하는 칸 수)
    local desiredTotal = ec.main0 + ec.bat0 + desiredGain
    if desiredTotal > maxTotal then
        desiredTotal = maxTotal
    end

    -- 이미 원하는 값 이상이면 아무 것도 안 함
    if total1 >= desiredTotal then
        return
    end

    -- 🔴 여기서부터는 AddActiveCharge를 쓰지 않고, 절대값으로 강제 세팅
    local finalMain = math.min(desiredTotal, maxCharges)
    local finalBat  = math.max(0, desiredTotal - finalMain)

    player:SetActiveCharge(finalMain, slot)
    if player.SetBatteryCharge then
        player:SetBatteryCharge(finalBat)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_Habit)


-- =================================================================================================================================================================================================================================================
-- Godhead (ID 331) — recursion guard
-- =================================================================================================================================================================================================================================================
local GODHEAD = 331
local _godheadGuard = false

function mod:OnEntityDamage_Godhead(entity, amount, flags, source, countdown)
    if _godheadGuard then return end
    if not (entity and entity:IsVulnerableEnemy()) then return end
    if not (source and source.Entity) then return end
    local tear = source.Entity:ToTear(); if not tear then return end
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

-- =================================================================================================================================================================================================================================================
-- Chocolate Milk (ID 69) + Money = Power (ID 109) — unified cache
-- =================================================================================================================================================================================================================================================
local CHOCOLATE_MILK = 69
local MONEY_IS_POWER = 109

function mod:OnEvaluateCache_All(player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        local mip = player:GetCollectibleNum(MONEY_IS_POWER)
        if mip > 0 then
            player.Damage = player.Damage + (player:GetNumCoins() * 0.04 * mip)
        end
        local ch = player:GetCollectibleNum(CHOCOLATE_MILK)
        local d = player:GetData()
        if ch > 0 then
            d.ChocoMin = 0.25 * ch
            d.ChocoMax = 2.0 + (ch - 1) * 1.0
        else
            d.ChocoMin, d.ChocoMax = nil, nil
        end
    end
end
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnEvaluateCache_All)

function mod:OnTearInit_Choco(tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player then return end
    if player:GetCollectibleNum(CHOCOLATE_MILK) <= 0 then return end
    local d = player:GetData()
    local minMult = d.ChocoMin or 0.25
    local maxMult = d.ChocoMax or 2.0
    local charge  = math.min(1.0, tear.Charge or 1.0)
    tear.CollisionDamage = tear.CollisionDamage * (minMult + (maxMult - minMult) * charge)
end
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTearInit_Choco)

-- =================================================================================================================================================================================================================================================
-- 9 Volt (ID 116)
-- =================================================================================================================================================================================================================================================
local NINE_VOLT = 116

function mod:OnUseItem_NineVolt(itemID, rng, player, flags, slot, varData)
    local c = player:GetCollectibleNum(NINE_VOLT)
    if c <= 1 then return end

    local s      = slot or ActiveSlot.SLOT_PRIMARY
    local amount = c - 1   -- 추가 스택당 +1칸

    AddActiveChargeCompat(player, amount, s)
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseItem_NineVolt)

-- =================================================================================================================================================================================
-- Stack Items — Hive Mind & BFF (Additive stacking)
-- =================================================================================================================================================================================

local mod = _G.mod or RegisterMod("Stack Items — Additive", 1)
_G.mod = mod

local game = Game()

-- =========================
-- 공통 파라미터 (한 곳에서 조절)
-- =========================
-- [합연산] 추가 스택당 +20%p (예: 1스택=×2.00, 2스택=×2.20, 3스택=×2.40 ...)
local ADD_PER_STACK = 0.50

-- BFF: 시각 크기 보정(선택) — 스택당 +5%p
local BFF_SCALE_PER_STACK = 0.05

-- Hive Mind: 파리/거미 스케일 보정(선택) — 스택당 +5%p (원치 않으면 0)
local HM_SCALE_PER_STACK  = 0.05

-- =========================
-- 엔진/상수
-- =========================
local HIVEMIND = 248
local BFFS     = 247

local BLUE_FLY    = FamiliarVariant.BLUE_FLY
local BLUE_SPIDER = FamiliarVariant.BLUE_SPIDER
local INCUBUS     = FamiliarVariant.INCUBUS
local SUCCUBUS    = FamiliarVariant.SUCCUBUS

-- =========================
-- 유틸
-- =========================
local function _isFlyOrSpiderFam(fam)
    return fam and (fam.Variant == BLUE_FLY or fam.Variant == BLUE_SPIDER)
end

-- 합연산 총배율: 1스택=2.0, 이후 스택당 +ADD_PER_STACK
local function _stack_mult_additive(stacks)
    if stacks <= 0 then return 1 end
    return 2 + ADD_PER_STACK * (stacks - 1)
end

-- BFF 본체(접촉 등 '절대배율'이 필요한 곳)용
local function _bff_stack_mult(bff)
    return _stack_mult_additive(bff)
end

-- ★ 엔진이 이미 ×2를 적용하는 대상(패밀리어 눈물/레이저/오라 등)에 주는 '추가배율'
local function _bff_extra_mult_for_engine_buffed(fam)
    if not fam or _isFlyOrSpiderFam(fam) then return 1 end
    local p = fam.Player
    if not p then return 1 end
    local bff = p:GetCollectibleNum(BFFS)
    if bff <= 0 then return 1 end
    return 1 + (ADD_PER_STACK * 0.5) * (bff - 1)
end

-- 같은 플레이어 소유 인큐버스 근접 탐색
local function _nearest_incubus_for_player(posEntity, ownerPlayer, radiusPx)
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

-- 인큐버스가 실제 쐈는지(간이 기하 검증)
local function _incubus_fired_this_tear(tear, incu)
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

-- 발사체(눈물/레이저) 1회 적용 헬퍼
local function _apply_bff_to_projectile_once_per_entity(ent, mult, baseGetter, baseSetter, tag)
    if mult == 1 then return end
    local d = ent:GetData()
    if d[tag .. "_applied"] then return end
    d[tag .. "_applied"] = true
    d[tag .. "_frames_left"] = 2
    local base = baseGetter(ent)
    d[tag .. "_base"] = base
    d[tag .. "_mult"] = mult
    baseSetter(ent, base * mult)
end

local function _tick_reassert_projectile(ent, baseGetter, baseSetter, tag)
    local d = ent:GetData()
    local left = d[tag .. "_frames_left"]
    if not left or left <= 0 then return end
    local base = d[tag .. "_base"]
    local mult = d[tag .. "_mult"] or 1
    if base and mult ~= 1 then
        baseSetter(ent, base * mult)
    end
    d[tag .. "_frames_left"] = left - 1
end

-- =================================================================================================================================================================================
-- Hive Mind (ID 248): 파리/거미 전용
-- =================================================================================================================================================================================
function mod:OnFamiliarUpdate_HiveMindOnly(fam)
    local player = fam.Player
    if not player then return end

    local v = fam.Variant
    if v ~= BLUE_FLY and v ~= BLUE_SPIDER then
        return
    end

    local hive = player:GetCollectibleNum(HIVEMIND)
    if hive <= 0 then
        return
    end

    local d = fam:GetData()
    if not d.__hive_base_init then
        d.__hive_base_damage = fam.CollisionDamage
        d.__hive_base_scale  = fam.SpriteScale or Vector(1, 1)
        d.__hive_base_size   = fam.Size or 10
        d.__hive_base_init   = true
    end

    local dmg_mult = _stack_mult_additive(hive)
    fam.CollisionDamage = (d.__hive_base_damage or fam.CollisionDamage) * dmg_mult

    if HM_SCALE_PER_STACK ~= 0 then
        local scale_mult = 1 + HM_SCALE_PER_STACK * (hive - 1)
        fam.SpriteScale = Vector(
            d.__hive_base_scale.X * scale_mult,
            d.__hive_base_scale.Y * scale_mult
        )
        fam.Size = (d.__hive_base_size or fam.Size) * scale_mult
    end
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_HiveMindOnly)

-- =================================================================================================================================================================================
-- BFFS (ID 247): 파리/거미 제외 패밀리어 본체 + 발사체 처리
-- =================================================================================================================================================================================
local function _apply_bff_to_familiar_body(fam)
    local player = fam.Player
    if not player or _isFlyOrSpiderFam(fam) then return end

    local bff = player:GetCollectibleNum(BFFS)
    if bff <= 0 then return end

    local d = fam:GetData()
    if not d.__bff_base_init then
        d.__bff_base_damage = fam.CollisionDamage
        d.__bff_base_scale  = fam.SpriteScale or Vector(1,1)
        d.__bff_base_size   = fam.Size or 10
        d.__bff_base_init   = true
    end

    local dmg_mult   = _bff_stack_mult(bff)
    local scale_mult = 1 + BFF_SCALE_PER_STACK * (bff - 1)

    fam.CollisionDamage = (d.__bff_base_damage or fam.CollisionDamage) * dmg_mult
    fam.SpriteScale     = Vector(d.__bff_base_scale.X * scale_mult, d.__bff_base_scale.Y * scale_mult)
    fam.Size            = (d.__bff_base_size or fam.Size) * scale_mult
end

function mod:OnFamiliarUpdate_BFF(fam)
    _apply_bff_to_familiar_body(fam)
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_BFF)

-- Tears (Incubus: INIT에는 표식, UPDATE에서 스냅샷 1회 적용)
function mod:OnTearInit_BFF(tear)
    local td = tear:GetData()
    if td.__bff_any_applied then return end

    local fam = (tear.Parent and tear.Parent:ToFamiliar()) or (tear.SpawnerEntity and tear.SpawnerEntity:ToFamiliar())
    if fam then
        if _isFlyOrSpiderFam(fam) then return end

        if fam.Variant == INCUBUS then
            td.__bff_incu_wait   = true
            td.__bff_incu_owner  = fam.Player and fam.Player.InitSeed or nil
            td.__bff_any_applied = true
            return
        else
            local mult = _bff_extra_mult_for_engine_buffed(fam)
            _apply_bff_to_projectile_once_per_entity(
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
        local incu = _nearest_incubus_for_player(tear, ownerP, 48)
        if incu and _incubus_fired_this_tear(tear, incu) then
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
            local incu = _nearest_incubus_for_player(tear, ownerP, 56)
            local mult = 1
            if incu then
                mult = _bff_extra_mult_for_engine_buffed(incu)
            end
            if mult ~= 1 then
                _apply_bff_to_projectile_once_per_entity(
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

    _tick_reassert_projectile(
        tear,
        function(t) return t.CollisionDamage end,
        function(t, v) t.CollisionDamage = v end,
        "__bff_tear"
    )
end
mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, mod.OnTearUpdate_BFF)

-- Lasers
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
    if not fam or _isFlyOrSpiderFam(fam) then ld.__bff_lz_done = true; return end

    local mult = _bff_extra_mult_for_engine_buffed(fam)
    if mult == 1 then ld.__bff_lz_done = true; return end

    if laser.CollisionDamage and laser.CollisionDamage > 0 then
        local base = laser.CollisionDamage
        laser.CollisionDamage = base * mult
        ld.__bff_lz_done = true
    end
end
mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_BFF)

-- Succubus aura
function mod:OnEntityTakeDamage_BFF(entity, amount, flags, source, countdown)
    if amount <= 0 then return end
    if not source or not source.Entity then return end

    local fam = source.Entity:ToFamiliar()
    if fam and fam.Variant == SUCCUBUS and fam.Player then
        local bff = fam.Player:GetCollectibleNum(BFFS)
        local mult = _bff_stack_mult(bff)
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

-- =================================================================================================================================================================================================================================================
-- Dead Bird (ID 117)
-- =================================================================================================================================================================================================================================================
local DEAD_BIRD = 117
local spawn_dead_bird = {true, true, true, true, true, true, true, true}

function mod:OnPlayerDamage_DeadBird(entity, amount, flags, source, countdown)
    if entity.Type ~= EntityType.ENTITY_PLAYER then return end
    local player = entity:ToPlayer()
    if not (player and player:HasCollectible(DEAD_BIRD)) then return end
    local extra = player:GetCollectibleNum(DEAD_BIRD) - 1
    if extra <= 0 then return end

    local idx = player.Index + 1
    if not spawn_dead_bird[idx] then return end
    for i = 1, extra do
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.DEAD_BIRD, 0, player.Position, Vector.Zero, player)
    end
    spawn_dead_bird[idx] = false
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_DeadBird)

function mod:OnNewRoom_DeadBird()
    spawn_dead_bird = {true, true, true, true, true, true, true, true}
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_DeadBird)

-- ======================================================================================================================================
-- Spear of Destiny (ID 400) — Additive stacking
-- ======================================================================================================================================
local SPEAR_OF_DESTINY = 400
local spearVariant, spearGuard = nil, false
local spearHitCD = {}

local ADD_PER_STACK = 0.10

local SPEAR_XSCALE_PER_STACK      = 0.15
local SPEAR_ADD_LEN_PER_STACK     = 12
local SPEAR_TIP_BACK_PAD          = 6
local SPEAR_BASE_HALF_WIDTH       = 10
local SPEAR_EXTRA_WIDTH_PER_STACK = 2
local SPEAR_COOLDOWN_FRAMES       = 3

local game = Game()

local function _spearKey(e) return pHash(e) end

local function _spear_total_mult(stacks)
    if stacks <= 1 then return 1 end
    return 1 + ADD_PER_STACK * (stacks - 1)
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
    local eff = src:ToEffect(); if not eff then return end

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

    local mult = _spear_total_mult(stacks)

    spearGuard = true
    entity:TakeDamage((amount or 0) * mult, flags or 0, source, countdown or 0)
    spearGuard = false

    return false
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityDamage_SpearOnly)

function mod:OnEffectUpdate_SpearLength(effect)
    if effect.Type ~= EntityType.ENTITY_EFFECT then return end
    local eff = effect:ToEffect(); if not eff then return end

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

    local dmgMult     = _spear_total_mult(stacks)
    local spearDamage = (player.Damage or 0) * 2 * dmgMult

    local frame = game:GetFrameCount()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsVulnerableEnemy() and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and not e:IsDead() then
            local rel = e.Position - tipStart
            local t   = rel:Dot(dir)
            if t >= 0 and t <= (SPEAR_TIP_BACK_PAD + addLen) then
                local perp = rel - dir * t
                if perp:Length() <= halfW then
                    local key = _spearKey(e)
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

-- ================================================================================================================================================================================================
-- Tech.5 (ID 244) — stack-aware extras that STOP at walls (no terrain piercing)
-- ================================================================================================================================================================================================
local mod = mod or RegisterMod and RegisterMod("Stackable Items RepPlus - Tech5", 1) or {}
local game = Game()

local TECH5 = 244
local TECH5_SPREAD_DEG = 5

local function markExtra(l) l:GetData().t5_extra = true end
local function isExtra(l)  return l:GetData().t5_extra == true end
local function handled(l)  return l:GetData().t5_handled == true end
local function setHandled(l) l:GetData().t5_handled = true end

local function pHash(e)
  if GetPtrHash then return GetPtrHash(e) end
  return tostring(e)
end

local EXCLUDE_VARIANTS = {
  [LaserVariant.LASER_BRIMSTONE or -1] = true,
  [LaserVariant.LASER_TECH2    or -1] = true,
  [LaserVariant.LIGHT_RING     or -1] = true,
}

local function looksLikeTech5(l)
  if not (l.SpawnerEntity and l.SpawnerEntity:ToPlayer()) then return false end
  local t = l.Timeout or 0
  if t <= 0 or t > 30 then return false end
  if EXCLUDE_VARIANTS[l.Variant or -1] then return false end
  return true
end

local function ShootAngleCompat(variant, angle, timeout, pos, owner)
  local ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner, owner)
  if ok and laser then return laser end
  ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner)
  if ok and laser then return laser end
  ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos)
  if ok and laser then return laser end
  ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner)
  if ok and laser then return laser end
  ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner, owner)
  if ok and laser then return laser end

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

local function _raycastMaxDist(pos, deg, fallback)
  local room = game:GetRoom()
  local FAR = 2000
  local dir = Vector.FromAngle(deg):Resized(FAR)

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
      local mid = (low + high) * 0.5
      local target = pos + dir:Resized(mid)
      local clear = false
      local ok, res = pcall(function() return room:CheckLine(pos, target, 0, 0, false, false) end)
      if ok and res then clear = true end
      if clear then low = mid else high = mid end
    end
    return math.max(24, high - 2)
  end

  return fallback or 240
end

local t5_origins, t5_extras = {}, {}

function mod:OnLaserUpdate_Tech5(laser)
  if isExtra(laser) or handled(laser) then return end
  local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
  if not player or not player:HasCollectible(TECH5) then return end

  setHandled(laser)
  if not looksLikeTech5(laser) then return end

  local count = player:GetCollectibleNum(TECH5)
  local extra = count - 1
  if extra <= 0 then return end

  local baseVariant = laser.Variant
  local baseAngle   = laser.AngleDegrees or 0
  local baseTimeout = laser.Timeout or 12
  local baseDamage  = laser.CollisionDamage or player.Damage
  local baseMaxDist = (laser.GetMaxDistance and laser:GetMaxDistance()) or nil

  local originHash = pHash(laser)
  t5_origins[originHash] = laser
  markExtra(laser)

  local half = (extra - 1) * 0.5
  for i = 0, extra - 1 do
    local ang = baseAngle + ((i - half) * TECH5_SPREAD_DEG)
    local spawnPos = laser.Position
    local new = ShootAngleCompat(baseVariant, ang, baseTimeout, spawnPos, player)
    if new then
      new.Position        = spawnPos
      new.SpawnerEntity   = player
      new.Parent          = player
      new.CollisionDamage = baseDamage

      local dist = baseMaxDist
      if (not dist) or dist <= 0 then
        dist = _raycastMaxDist(spawnPos, ang, 240)
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

function mod:OnNewRoom_Tech5() t5_origins, t5_extras = {}, {} end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Tech5)
function mod:OnGameStart_Tech5() t5_origins, t5_extras = {}, {} end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Tech5)

-- ======================================================================
-- Mini Pack (ID 204)
-- ======================================================================
local MINIPACK = 204
local game = Game()

local ALLOWED_VARIANTS = {
    PickupVariant.PICKUP_COIN,
    PickupVariant.PICKUP_HEART,
    PickupVariant.PICKUP_KEY,
    PickupVariant.PICKUP_BOMB,
    PickupVariant.PICKUP_BATTERY
}

local function spawnAllowedPickup(rng, player)
    local room = game:GetRoom()
    local pos  = room:FindFreePickupSpawnPosition(player.Position, 0, true)
    local idx = rng:RandomInt(#ALLOWED_VARIANTS) + 1
    local variant = ALLOWED_VARIANTS[idx]
    local subtype = 0
    Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, pos, Vector.Zero, player)
end

function mod:OnEntityTakeDamage_MiniPack(ent, amount, flags, source, countdown)
    local player = ent:ToPlayer()
    if not player or not player:HasCollectible(MINIPACK) then return end

    local count = player:GetCollectibleNum(MINIPACK)
    if count <= 0 then return end

    local rng = player:GetCollectibleRNG(MINIPACK)

    for i = 1, count do
        if rng:RandomFloat() < 0.5 then
            spawnAllowedPickup(rng, player)
        end
    end
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityTakeDamage_MiniPack)

-- =================================================================================================================================================================================================================================================
-- Eye Sore (ID 558)
-- =================================================================================================================================================================================================================================================
local EYESORE = 558
local FIXED_PROC = 0.30

function mod:OnTear_EyeSore(tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(EYESORE) then return end

    local c = player:GetCollectibleNum(EYESORE)
    if c <= 0 then return end

    local frame = game:GetFrameCount()
    local d = player:GetData()
    d.__eyesore_last_fire_frame = d.__eyesore_last_fire_frame or -1

    if d.__eyesore_last_fire_frame == frame then return end

    local rng = player:GetCollectibleRNG(EYESORE)
    if rng:RandomFloat() >= FIXED_PROC then
        return
    end

    d.__eyesore_last_fire_frame = frame
    local extraMin, extraMax = c, c + 2
    local extra = rng:RandomInt(extraMax - extraMin + 1) + extraMin

    local speed = 10 / (player.MaxFireDelay / 10 + 1)
    for i = 1, extra do
        local angle = rng:RandomFloat() * 360.0
        local vel = Vector.FromAngle(angle):Resized(speed)
        local t = player:FireTear(player.Position, vel, false, false, false)
        if t then
            t.CollisionDamage = player.Damage
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTear_EyeSore)

-- =================================================================================================================================================================================================================================================
-- Holy Light — stackable damage + size + real AoE pulse
-- =================================================================================================================================================================================================================================================
local HOLY_LIGHT = CollectibleType.COLLECTIBLE_HOLY_LIGHT
local V_CRACK    = EffectVariant.CRACK_THE_SKY
local game       = Game()

local function dmgMult(count)
    return (count <= 0) and 1.0 or (3.0 * (1.2 ^ (count - 1)))
end
local function visMult(count)
    return (count <= 0) and 1.0 or (1.0 + 0.03 * (count - 1))
end

local function ensureBase(eff)
    local d = eff:GetData()
    if d.__hl_base_saved then return end
    d.__hl_base_saved  = true
    d.__hl_base_scale  = eff.SpriteScale or Vector(1,1)
    d.__hl_base_size   = eff.Size or 1
end

local function applyMainPillar(eff)
    ensureBase(eff)
    local d = eff:GetData()

    local p = eff.SpawnerEntity and eff.SpawnerEntity:ToPlayer()
    if not p then
        local nearest, best = nil, 1e12
        for i = 0, game:GetNumPlayers() - 1 do
            local pl = Isaac.GetPlayer(i)
            local dist = (pl.Position - eff.Position):LengthSquared()
            if dist < best then best, nearest = dist, pl end
        end
        p = nearest
    end
    local count = p and p:GetCollectibleNum(HOLY_LIGHT) or 0

    local sMul = visMult(count)
    eff.SpriteScale = Vector(d.__hl_base_scale.X * sMul, d.__hl_base_scale.Y * sMul)

    if p then
        eff.CollisionDamage = p.Damage * dmgMult(count)
    end

    return p, count
end

local VISUAL_R0    = 11.5
local INNER_RATIO  = 0.85
local MAX_RADIUS   = 120.0
local MIN_RADIUS   = 6.0
local PULSE_FRAMES = {1,2,3}
local DMG_FLAGS    = (DamageFlag.DAMAGE_NO_PENALTIES or 0)

local function frameIn(tbl, f) for _,v in ipairs(tbl) do if v==f then return true end end return false end
local function isDamageableEnemy(ent)
    local npc = ent and ent:ToNPC()
    if not npc then return false end
    if not npc:IsVulnerableEnemy() then return false end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return false end
    return true
end

local function applyAoePulse(eff, player, count)
    if not player then return end

    local f = eff.FrameCount
    if not frameIn(PULSE_FRAMES, f) then return end

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

    local desiredDmg = player.Damage * dmgMult(count)
    local ents = Isaac.FindInRadius(eff.Position, radius, EntityPartition.ENEMY)

    for _, e in ipairs(ents) do
        if isDamageableEnemy(e) then
            local id = GetPtrHash(e)
            if not d.__hl_hit[id] then
                e:TakeDamage(desiredDmg, DMG_FLAGS, EntityRef(player), 0)
                d.__hl_hit[id] = true
            end
        end
    end
end

function mod:OnCrackInit(eff)
    if eff.Variant ~= V_CRACK then return end
    local p, count = applyMainPillar(eff)
    applyAoePulse(eff, p, count)
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.OnCrackInit)

function mod:OnCrackUpdate(eff)
    if eff.Variant ~= V_CRACK then return end
    local p, count = applyMainPillar(eff)
    applyAoePulse(eff, p, count)
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnCrackUpdate)

-- (Revelation / Mars / Trinity Shield 부분은 원본에서 주석 처리된 상태 그대로 유지)


-- -- =================================================================================================
-- -- Revelation (ID 643) — multi-beam from mouth, eased fan, TERRAIN+ENEMY PIERCING
-- --  - FIX: robust stack counting (includes hidden/mod stacks, effect stacks) + optional force override
-- -- =================================================================================================
-- local mod  = mod or (RegisterMod and RegisterMod("Stackable Items RepPlus - Revelation Piercing", 1)) or {}
-- local game = Game()

-- -- ===== PRESETS =====
-- local REVELATION          = 643
-- local REV_TOTAL_SPAN_DEG  = 42      -- total fan span
-- local REV_EDGE_RADIUS_MIN = 0.75    -- edge radius taper (0.7~0.9 good)
-- local REV_EDGE_ALPHA_MIN  = 0.85    -- edge alpha taper
-- local MOUTH_PUSH_PIX      = 10      -- small forward push from mouth
-- local MOUTH_Y_OFFSET_BASE = -22     -- render offset upward so it doesn't look like feet

-- -- 🔧 디버그/강제 옵션
-- local DEBUG_REV_DETECT       = false
-- local DEBUG_LOG_STACKS       = true   -- 스택 계산 로그
-- local REV_FORCE_STACKS       = 0      -- 0이면 자동 계산. 테스트용으로 원하시는 스택 수를 지정 가능.

-- -- ===== helpers: flags & hashing =====
-- local function markExtra(l)      l:GetData().rev_extra   = true end
-- local function isExtra(l)        return l:GetData().rev_extra   == true end
-- local function handled(l)        return l:GetData().rev_handled == true end
-- local function setHandled(l)     l:GetData().rev_handled = true end
-- local function pHash(e) if GetPtrHash then return GetPtrHash(e) end; return tostring(e) end

-- -- (optional) whitelist if you know the exact variant in your build
-- local KNOWN_REV_VARIANTS = {
--   -- [LaserVariant.LIGHT_BEAM] = true,
-- }
-- local learnedRevVariant = nil

-- -- ShootAngle compatibility wrapper
-- local function ShootAngleCompat(variant, angle, timeout, pos, owner)
--   local ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner, owner)
--   if ok and laser then return laser end
--   ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner)
--   if ok and laser then return laser end
--   ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos)
--   if ok and laser then return laser end
--   ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner)
--   if ok and laser then return laser end
--   local ent = Isaac.Spawn(EntityType.ENTITY_LASER, variant, 0, pos, Vector.Zero, owner)
--   local l = ent and ent:ToLaser()
--   if l then
--     l.AngleDegrees  = angle
--     l.Timeout       = timeout
--     l.SpawnerEntity = owner
--     l.Parent        = owner
--     return l
--   end
--   return nil
-- end

-- -- Revelation laser detection (loose → learn)
-- local function looksLikeRevelationLaser(l)
--   if not (l and l.SpawnerEntity and l.SpawnerEntity:ToPlayer()) then return false end
--   local t = l.Timeout or 0
--   if t <= 0 or t > 60 then return false end
--   local v = l.Variant or -1
--   if KNOWN_REV_VARIANTS[v] then return true end
--   if learnedRevVariant and v == learnedRevVariant then return true end
--   return true
-- end

-- -- easing (0..1 → 0..1) for prettier spacing
-- local function easeInOut(t) return t * t * (3 - 2 * t) end

-- -- mouth/tear spawn anchor (position + render offset)
-- local function getMouthAnchor(player, angleDeg)
--   local dir = Vector.FromAngle(angleDeg):Resized(MOUTH_PUSH_PIX)
--   local ok, pos = pcall(function() return player:GetTearSpawnPos(dir, true) end)
--   if not ok or not pos then pos = player.Position + dir end
--   local spriteOff = player.SpriteOffset or Vector.Zero
--   local offset = Vector(0, MOUTH_Y_OFFSET_BASE) + spriteOff
--   return pos, offset
-- end

-- -- ===== robust stack counting =====
-- local function getRevStacks(player)
--   -- 1) 강제 지정이 있으면 그것을 사용
--   if REV_FORCE_STACKS and REV_FORCE_STACKS > 0 then
--     return REV_FORCE_STACKS
--   end

--   -- 2) 일반 카운트 + 숨김/변형 포함 카운트 시도(Rep+에선 두번째 인자 허용)
--   local count_basic = 0
--   local ok_basic, res_basic = pcall(function() return player:GetCollectibleNum(REVELATION) end)
--   if ok_basic and res_basic then count_basic = res_basic end

--   local count_inclHidden = 0
--   local ok_hidden, res_hidden = pcall(function() return player:GetCollectibleNum(REVELATION, true) end)
--   if ok_hidden and res_hidden then
--     count_inclHidden = res_hidden
--   else
--     count_inclHidden = count_basic
--   end

--   -- 3) 이펙트(일시 스택)까지 더해 보기
--   local effect_cnt = 0
--   local effects = player:GetEffects and player:GetEffects()
--   if effects and effects.GetCollectibleEffectNum then
--     local ok_eff, res_eff = pcall(function() return effects:GetCollectibleEffectNum(REVELATION) end)
--     if ok_eff and res_eff then effect_cnt = res_eff end
--   end

--   local stacks = math.max(count_basic, count_inclHidden) + effect_cnt

--   -- 4) 혹시 다른 모드에서 커스텀 스택 변수를 써 준다면 여기서 병합
--   --    예: if mod.RevExtraStacks then stacks = stacks + mod.RevExtraStacks end

--   if DEBUG_LOG_STACKS then
--     Isaac.DebugString(string.format("[REV] stacks: basic=%d, inclHidden=%d, effects=%d -> final=%d",
--       count_basic, count_inclHidden, effect_cnt, stacks))
--   end
--   return math.max(1, stacks)
-- end

-- -- ===== state =====
-- local rev_origins, rev_extras, rev_follow = {}, {}, {}

-- -- ===== utility: force piercing (terrain + enemies) on a laser =====
-- local function makePiercing(laser, fallbackMax)
--   if laser.SetMaxDistance then
--     local cur = 0
--     if laser.GetMaxDistance then cur = laser:GetMaxDistance() or 0 end
--     laser:SetMaxDistance(math.max(cur, fallbackMax or 2000))
--   end
--   if laser.GridCollisionClass ~= nil then
--     laser.GridCollisionClass = GridCollisionClass.GRIDCOLL_NONE
--   end
--   if TearFlags and laser.TearFlags ~= nil then
--     laser.TearFlags = (laser.TearFlags | TearFlags.TEAR_PIERCING | (TearFlags.TEAR_CONTINUUM or 0))
--   end
-- end

-- -- ===== core =====
-- function mod:OnLaserUpdate_Revelation(laser)
--   if isExtra(laser) or handled(laser) then return end
--   local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
--   if not player or not player:HasCollectible(REVELATION) then return end

--   setHandled(laser)
--   if not looksLikeRevelationLaser(laser) then return end

--   if not learnedRevVariant then
--     learnedRevVariant = laser.Variant
--     if DEBUG_REV_DETECT then
--       Isaac.DebugString(string.format("[REV] learn variant=%s timeout=%d", tostring(learnedRevVariant), laser.Timeout or -1))
--     end
--   end

--   local stacks      = getRevStacks(player)
--   local extra       = math.max(0, stacks - 1)
--   local baseVariant = laser.Variant
--   local baseAngle   = laser.AngleDegrees or 0
--   local baseTimeout = laser.Timeout or 20
--   local baseDamage  = laser.CollisionDamage or player.Damage

--   -- ★ original from mouth + piercing
--   local mouthPos, mouthOff = getMouthAnchor(player, baseAngle)
--   laser.Position       = mouthPos
--   laser.PositionOffset = mouthOff
--   makePiercing(laser, 2000)

--   local originHash = pHash(laser)
--   rev_origins[originHash] = laser
--   markExtra(laser)
--   rev_follow[originHash] = { player = player }

--   if extra <= 0 then return end

--   -- eased fan around baseAngle with fixed total span
--   local n    = extra
--   local span = REV_TOTAL_SPAN_DEG
--   for i = 0, n - 1 do
--     local t0 = (i + 0.5) / n
--     local t  = easeInOut(t0)
--     local u  = (t - 0.5) * 2.0
--     local ang = baseAngle + (u * span * 0.5)

--     local spawnPos, spawnOff = getMouthAnchor(player, ang)
--     local new = ShootAngleCompat(baseVariant, ang, baseTimeout, spawnPos, player)
--     if new then
--       new.Position        = spawnPos
--       new.PositionOffset  = spawnOff
--       new.SpawnerEntity   = player
--       new.Parent          = player
--       new.CollisionDamage = baseDamage

--       -- piercing for duplicates
--       makePiercing(new, 2000)

--       -- inherit look/flags
--       if laser.TearFlags then new.TearFlags = (laser.TearFlags | TearFlags.TEAR_PIERCING | (TearFlags.TEAR_CONTINUUM or 0)) end
--       if (new.GridCollisionClass ~= nil) then
--         new.GridCollisionClass = GridCollisionClass.GRIDCOLL_NONE
--       end
--       new.DepthOffset = laser.DepthOffset

--       -- edge softness
--       local edgeW = math.abs(u)
--       if new.Radius then new.Radius = (laser.Radius or new.Radius or 10) * (1 - (1-REV_EDGE_RADIUS_MIN)*edgeW) end
--       if laser.Color then
--         local c = Color(laser.Color.R, laser.Color.G, laser.Color.B,
--                         (laser.Color.A or 1) * (1 - (1-REV_EDGE_ALPHA_MIN)*edgeW),
--                         laser.Color.RO, laser.Color.GO, laser.Color.BO)
--         new.Color = c
--       end

--       new:Update()

--       local d = new:GetData()
--       d.rev_extra, d.rev_handled, d.rev_followHash = true, true, originHash
--       table.insert(rev_extras, new)
--     end
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_Revelation)

-- -- keep original anchored at mouth; extras follow original (including PositionOffset)
-- function mod:OnPostUpdate_RevelationSnap()
--   for hash, info in pairs(rev_follow) do
--     local origin = rev_origins[hash]
--     if origin and origin:Exists() and info.player and info.player:Exists() then
--       local ang = origin.AngleDegrees or 0
--       local p, off = getMouthAnchor(info.player, ang)
--       origin.Position       = p
--       origin.PositionOffset = off
--       makePiercing(origin, 2000)
--     else
--       rev_follow[hash] = nil
--     end
--   end
--   for i = #rev_extras, 1, -1 do
--     local l = rev_extras[i]
--     if (not l) or (not l:Exists()) then
--       table.remove(rev_extras, i)
--     else
--       local hash   = l:GetData() and l:GetData().rev_followHash
--       local origin = hash and rev_origins[hash] or nil
--       if origin and origin:Exists() then
--         l.Position       = origin.Position
--         l.PositionOffset = origin.PositionOffset
--         makePiercing(l, 2000)
--       else
--         if hash then rev_origins[hash] = nil end
--       end
--     end
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnPostUpdate_RevelationSnap)

-- -- reset state
-- function mod:OnNewRoom_Revelation() rev_origins, rev_extras, rev_follow = {}, {}, {} end
-- mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Revelation)
-- function mod:OnGameStart_Revelation() rev_origins, rev_extras, rev_follow = {}, {}, {} end
-- mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Revelation)

-- -- ======================================================================
-- -- Mars — Delayed Afterimage (No Tears)
-- -- ======================================================================
-- local mod  = RegisterMod("Mars Delayed Trail", 1)
-- local game = Game()
-- local MARS = CollectibleType.COLLECTIBLE_MARS

-- -- ====== Tuning =========================================================
-- local START_THR     = 12.0   -- 대시 시작 속도 임계값
-- local KEEP_THR      = 7.5    -- 대시 유지/종료 임계값
-- local PATH_MAX      = 150    -- 경로 최대 기록 프레임
-- local SAMPLE_SKIP   = 0      -- 0=매 프레임 기록, 1=격프레임 등
-- local DELAY_F       = 36     -- 대시 종료 후 잔상 출력 시작 지연(0.6s@60fps)
-- local TRAIL_EVERY   = 2      -- 잔상 찍는 간격(숫자 낮을수록 촘촘)
-- local TRAIL_TIMEOUT = 8      -- 잔상 유지 프레임(짧을수록 흐릿)
-- local TRAIL_ALPHA   = 0.7    -- 잔상 투명도(0~1)

-- -- ====== State ==========================================================
-- local dash  = {}  -- [pHash] = { active=false, path={}, skip=0 }
-- local reels = {}  -- 재생 큐: { owner=pHash, idx=1, startF, step=TRAIL_EVERY, visTick=0, path={} }

-- local function pHash(e) return (GetPtrHash and GetPtrHash(e)) or e.InitSeed end

-- -- 0) 바닐라 Mars 잔상 즉시 제거
-- function mod:OnEffectInit(eff)
--   if eff.Variant == EffectVariant.PLAYER_TRAIL then
--     local p = eff.SpawnerEntity and eff.SpawnerEntity:ToPlayer()
--     if p and p:HasCollectible(MARS) then
--       eff:Remove()
--     end
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.OnEffectInit)

-- -- 1) 대시 경로 기록
-- function mod:OnPostPlayerUpdate(pl)
--   if not pl:HasCollectible(MARS) then return end

--   local key = pHash(pl)
--   local d   = dash[key]
--   if not d then d = {active=false, path={}, skip=0}; dash[key] = d end

--   local vlen = pl.Velocity:Length()

--   -- 대시 시작
--   if (not d.active) and vlen >= START_THR then
--     d.active = true
--     d.path   = { pl.Position }
--     d.skip   = 0
--     return
--   end

--   -- 대시 중 기록
--   if d.active then
--     if vlen < KEEP_THR then
--       -- 대시 종료 → 지연 잔상 재생 예약
--       d.active = false
--       if #d.path >= 3 then
--         -- 경로 사본 만들어서 재생 큐에 등록
--         local copy = {}
--         for i=1,#d.path do copy[i] = d.path[i] end
--         table.insert(reels, {
--           owner  = key,
--           path   = copy,
--           idx    = 1,
--           startF = game:GetFrameCount() + DELAY_F,
--           step   = TRAIL_EVERY,
--           visTick= 0
--         })
--       end
--       return
--     end

--     -- 계속 기록
--     d.skip = d.skip + 1
--     if d.skip >= (SAMPLE_SKIP + 1) then
--       d.skip = 0
--       table.insert(d.path, pl.Position)
--       if #d.path > PATH_MAX then table.remove(d.path, 1) end
--     end
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.OnPostPlayerUpdate)

-- -- 2) 지연 후 커스텀 잔상 생성
-- local function spawnTrailAt(pos, owner)
--   local e = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.PLAYER_TRAIL, 0, pos, Vector.Zero, owner)
--   local fx = e and e:ToEffect()
--   if fx then
--     fx.Timeout = TRAIL_TIMEOUT
--     fx.Color   = Color(1,1,1,TRAIL_ALPHA,0,0,0) -- 투명도 조절
--   end
-- end

-- function mod:OnPostUpdate()
--   if #reels == 0 then return end
--   local frame = game:GetFrameCount()

--   for i = #reels, 1, -1 do
--     local r = reels[i]
--     if frame < r.startF then goto cont end

--     -- 소유자 찾기(선택적: 없으면 그냥 진행)
--     local owner
--     for p=0, game:GetNumPlayers()-1 do
--       local pl = Isaac.GetPlayer(p)
--       if pHash(pl) == r.owner then owner = pl break end
--     end

--     -- 일정 간격으로만 잔상 생성
--     r.visTick = r.visTick + 1
--     if (r.visTick % r.step) == 0 then
--       r.idx = r.idx + 1
--       local pos = r.path[r.idx]
--       if not pos then
--         table.remove(reels, i) -- 끝
--         goto cont
--       end
--       spawnTrailAt(pos, owner)
--     end

--     ::cont::
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnPostUpdate)

-- -- 3) 방 이동 시 정리
-- function mod:OnNewRoom()
--   dash  = {}
--   reels = {}
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)

-- ------------------------- Trinity Shield (ID 243) — FULL (PNG sprite segments) -------------------------
-- local TRINITY_SHIELD = 243

-- -- 판정(막기): 16중첩 즈음 전방위
-- local TS_BASE_HALF_DEG   = 12   -- 기본 반각(도)
-- local TS_ADD_HALF_DEG    = 12   -- 스택당 반각 증가(도)
-- local TS_BASE_RADIUS     = 48   -- 기본 반경(픽셀)
-- local TS_ADD_RADIUS      = 4    -- 스택당 반경 증가(픽셀)

-- -- 시각(렌더)
-- local TS_VIS_RADIUS_BASE = 20   -- 시각 세그먼트 반경 기본
-- local TS_VIS_RADIUS_ADD  = 2    -- 스택당 시각 반경 증가
-- local TS_SEG_SPACING_DEG = 12   -- 세그먼트 간 각 간격(작을수록 촘촘)
-- local TS_SEG_SCALE       = 0.75 -- 세그먼트 스프라이트 스케일

-- -- 마지막 조준 방향(입력 없으면 유지)
-- local ts_lastAim = Vector(1, 0)
-- local function getAimDir(p)
--   local aim = nil
--   if p.GetAimDirection ~= nil then aim = p:GetAimDirection() end
--   if aim ~= nil then
--     if aim:Length() > 0.1 then
--       ts_lastAim = aim:Normalized()
--       return ts_lastAim
--     end
--   end
--   local d = Direction.NO_DIRECTION
--   if p.GetFireDirection ~= nil then d = p:GetFireDirection() end
--   if d ~= Direction.NO_DIRECTION then
--     if d == Direction.LEFT  then ts_lastAim = Vector(-1, 0) end
--     if d == Direction.RIGHT then ts_lastAim = Vector( 1, 0) end
--     if d == Direction.UP    then ts_lastAim = Vector( 0,-1) end
--     if d == Direction.DOWN  then ts_lastAim = Vector( 0, 1) end
--     return ts_lastAim
--   end
--   return ts_lastAim
-- end

-- -- 1) 판정: 부채꼴(wedge) 안의 적 발사체 제거
-- function mod:OnUpdate_TrinityShield()
--   local player = Isaac.GetPlayer(0)
--   if player == nil or player:IsDead() then return end

--   local stacks = player:GetCollectibleNum(TRINITY_SHIELD)
--   if stacks <= 0 then return end

--   local aimDir    = getAimDir(player)
--   local halfAngle = TS_BASE_HALF_DEG + TS_ADD_HALF_DEG * (stacks - 1)
--   if halfAngle > 180 then halfAngle = 180 end
--   local radius    = TS_BASE_RADIUS + TS_ADD_RADIUS * (stacks - 1)
--   local center    = player.Position

--   local ents = Isaac.GetRoomEntities()
--   for i = 1, #ents do
--     local ent = ents[i]
--     if ent.Type == EntityType.ENTITY_PROJECTILE then
--       local proj = ent:ToProjectile()
--       if proj ~= nil and proj:Exists() then
--         if not proj:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER) then
--           local v = proj.Position - center
--           local dist = v:Length()
--           if dist <= radius then
--             if halfAngle >= 180 then
--               proj:Die()
--             else
--               if dist > 0.0001 then
--                 local cosv = aimDir:Dot(v / dist)
--                 if cosv > 1 then cosv = 1 end
--                 if cosv < -1 then cosv = -1 end
--                 local angdeg = math.deg(math.acos(cosv))
--                 if angdeg <= halfAngle then
--                   proj:Die()
--                 end
--               end
--             end
--           end
--         end
--       end
--     end
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_TrinityShield)

-- -- 2) 스프라이트 로더: anm2를 베이스로 읽고 PNG 교체
-- local ts_sprite = nil
-- local TS_PNG = "gfx/effects/effect_243_trinityshield.png"   -- 너가 알려준 파일 (상대경로!)
-- local TS_BASE_ANM2 = "gfx/005.000_collectible.anm2"         -- 1프레임짜리 베이스

-- local function ensureTSSprite()
--   if ts_sprite ~= nil then return end
--   local s = Sprite()
--   local ok1 = pcall(function() s:Load(TS_BASE_ANM2, true) end)
--   if not ok1 then
--     ts_sprite = false
--     return
--   end
--   local ok2 = pcall(function()
--     s:ReplaceSpritesheet(0, TS_PNG)
--     s:LoadGraphics()
--     s:Play("Idle", true)
--   end)
--   if ok2 then
--     s.Scale = Vector(TS_SEG_SCALE, TS_SEG_SCALE)
--     ts_sprite = s
--   else
--     ts_sprite = false
--   end
-- end

-- -- 3) 시각: 도트(항상) + 스프라이트(가능하면 덮어쓰기)
-- function mod:OnPlayerRender_TS(_, _)
--   local player = Isaac.GetPlayer(0)
--   if player == nil or player:IsDead() then return end

--   local stacks = player:GetCollectibleNum(TRINITY_SHIELD)
--   if stacks <= 0 then return end

--   ensureTSSprite()

--   local aim    = getAimDir(player)
--   local half   = TS_BASE_HALF_DEG + TS_ADD_HALF_DEG * (stacks - 1)
--   if half > 180 then half = 180 end
--   local radius = TS_VIS_RADIUS_BASE + TS_VIS_RADIUS_ADD * (stacks - 1)
--   local baseDeg = aim:GetAngleDegrees()

--   local ang = -half
--   while ang <= half do
--     local deg = baseDeg + ang
--     local dir = Vector(1, 0):Rotated(deg)
--     local screenPos = Isaac.WorldToRenderPosition(player.Position + dir * radius)

--     -- 도트(항상)
--     Isaac.RenderText(".", screenPos.X, screenPos.Y, 1, 1, 1, 1)

--     -- 스프라이트가 준비돼 있으면 그 위에 덮어그리기
--     if ts_sprite and ts_sprite ~= false then
--       ts_sprite.Rotation = deg
--       ts_sprite:Render(screenPos, Vector.Zero, Vector.Zero)
--     end

--     ang = ang + TS_SEG_SPACING_DEG
--   end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, mod.OnPlayerRender_TS)
