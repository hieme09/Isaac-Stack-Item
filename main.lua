-- =========================================================
-- Stackable Items RepPlus - Modular Loader
-- =========================================================
local mod = RegisterMod("Stackable Items RepPlus", 1)

-- 전역 API 객체 (다른 모드와 전역 충돌을 피하기 위해 API를 한 곳에 모음)
StackItemAPI = {}

function StackItemAPI:PrintDebug(str)
    Isaac.DebugString("[Stackable Items] " .. tostring(str))
end

-- 1. 유틸 로드
local utils = require("scripts.utils")

-- 2. 로드할 아이템 모듈 목록
local itemModules = {
    "scripts.items.habit",
    "scripts.items.godhead",
    "scripts.items.chocolate_milk_mip",
    "scripts.items.nine_volt",
    "scripts.items.hive_mind_bffs",
    "scripts.items.dead_bird",
    "scripts.items.spear_of_destiny",
    "scripts.items.tech5",
    "scripts.items.mini_pack",
    "scripts.items.eye_sore",
    "scripts.items.holy_light",
}

-- 3. 모듈 초기화
for _, modulePath in ipairs(itemModules) do
    local ok, moduleFunc = pcall(require, modulePath)
    if ok and type(moduleFunc) == "function" then
        moduleFunc(mod, utils)
    else
        local err = moduleFunc or "Unknown error"
        print("[Stackable Items] Failed to load module: " .. modulePath .. " - Error: " .. tostring(err))
    end
end

print("[Stackable Items] Modular refactor loaded successfully.")
