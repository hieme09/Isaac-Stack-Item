local itemConfig = Isaac.GetItemConfig()

return function(mod, utils)
    -- HABIT ID 안전하게 감지 (The Habit ID: 156)
    local HABIT = Isaac.GetItemIdByName("The Habit")
    if HABIT == -1 or not HABIT then HABIT = 156 end
    
    mod.extraCharge = nil

    function mod:OnPlayerDamage_Habit(entity, amount, flags, source, countdown)
        if entity.Type ~= EntityType.ENTITY_PLAYER then return end
        local player = entity:ToPlayer()
        if not player then return end

        local count = player:GetCollectibleNum(HABIT)
        if count <= 0 then return end

        local slot
        if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= 0 then
            slot = ActiveSlot.SLOT_PRIMARY
        elseif player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) ~= 0 then
            slot = ActiveSlot.SLOT_SECONDARY
        else
            return
        end

        local main0 = player:GetActiveCharge(slot)
        local bat0  = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0

        mod.extraCharge = {
            index  = player.ControllerIndex,
            slot   = slot,
            stacks = count,
            main0  = main0,
            bat0   = bat0,
        }
    end
    mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_Habit)

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

        local cfg        = itemConfig:GetCollectible(activeItem)
        local maxCharges = (cfg and cfg.MaxCharges) or 6
        local maxTotal   = maxCharges * 2

        local extraStacks = math.max(0, stacks - 1)
        local desiredGain = 1 + extraStacks

        local main1  = player:GetActiveCharge(slot)
        local bat1   = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0
        local total1 = main1 + bat1

        local desiredTotal = ec.main0 + ec.bat0 + desiredGain
        if desiredTotal > maxTotal then
            desiredTotal = maxTotal
        end

        if total1 >= desiredTotal then
            return
        end

        local finalMain = math.min(desiredTotal, maxCharges)
        local finalBat  = math.max(0, desiredTotal - finalMain)

        player:SetActiveCharge(finalMain, slot)
        if player.SetBatteryCharge then
            -- The Battery(오버차지) 슬롯까지 정확히 반영 (Sharp Plug 등과 충돌 방지)
            player:SetBatteryCharge(finalBat, slot)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_Habit)
end
