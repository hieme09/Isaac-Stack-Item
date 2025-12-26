local game = Game()

return function(mod, utils)
    -- NINE_VOLT ID 안전하게 감지 (9 Volt ID: 116)
    local NINE_VOLT = Isaac.GetItemIdByName("9 Volt")
    if NINE_VOLT == -1 or not NINE_VOLT then NINE_VOLT = 116 end

    -- 다음 프레임에 적용할 추가 충전 대기열
    mod.nineVoltPending = mod.nineVoltPending or {}

    function mod:OnUseItem_NineVolt(itemID, rng, player, flags, slot, varData)
        if not player then return end

        local c = player:GetCollectibleNum(NINE_VOLT)
        if c <= 1 then return end

        -- 콜백에서 받은 슬롯을 우선 사용 (없으면 PRIMARY)
        local s = slot or ActiveSlot.SLOT_PRIMARY

        -- 가드: 같은 플레이어가 같은 프레임에 중복 등록되는 것 방지
        local d = player:GetData()
        local f = game:GetFrameCount()
        d.__ninevolt_last_frame = d.__ninevolt_last_frame or -999
        if d.__ninevolt_last_frame == f then
            return
        end
        d.__ninevolt_last_frame = f

        -- 추가 스택당 +1 충전 (엔진이 첫 +1은 이미 처리함)
        table.insert(mod.nineVoltPending, {
            player = player,
            slot   = s,
            add    = (c - 1),
            frame  = f + 1, -- 엔진 처리 이후 다음 프레임에 적용
        })
    end
    mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseItem_NineVolt)

    function mod:OnUpdate_NineVolt()
        if not mod.nineVoltPending or #mod.nineVoltPending == 0 then return end

        local frame = game:GetFrameCount()
        for i = #mod.nineVoltPending, 1, -1 do
            local info = mod.nineVoltPending[i]
            local p = info.player
            if (not p) or (not p:Exists()) then
                table.remove(mod.nineVoltPending, i)
            else
                if frame >= (info.frame or frame) then
                    utils.AddActiveChargeCompat(p, info.add or 0, info.slot)
                    table.remove(mod.nineVoltPending, i)
                end
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_NineVolt)
end
