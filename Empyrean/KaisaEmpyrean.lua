local function class()
    return setmetatable(
        {},
        {
            __call = function(self, ...)
                local result = setmetatable({}, {__index = self})
                result:__init(...)

                return result
            end
        }
    )
end

local Kaisa = class()
Kaisa.version = 1.93
require "FF15Menu"
require "utils"
local Orbwalker = require "ModernUOL"
local DreamTS = require("DreamTS")

function Kaisa:__init()
    self.qRange = 600
    self.w = {
        searchRange = 400,
        speed = 1750,
        range = 2500,
        delay = 0.4,
        width = 200,
        collision = {
            ["Wall"] = true,
            ["Hero"] = true,
            ["Minion"] = true
        }
    }
    self.LastCasts = {
        Q = nil,
        W = nil
    }

    self.turrets = {}
    for i, turret in pairs(ObjectManager:GetEnemyTurrets()) do
        self.turrets[turret.networkId] = {object = turret, range = 775 + 25}
    end
    self:Menu()
    self.TS =
        DreamTS(
        self.menu.dreamTs,
        {
            Damage = DreamTS.Damages.AD
        }
    )
    AddEvent(
        Events.OnTick,
        function()
            self:OnTick()
        end
    )
    AddEvent(
        Events.OnBuffGain,
        function(obj, buff)
            self:OnBuffGain(obj, buff)
        end
    )
    AddEvent(
        Events.OnBuffLost,
        function(obj, buff)
            self:OnBuffLost(obj, buff)
        end
    )

    AddEvent(
        Events.OnDraw,
        function()
            self:OnDraw()
        end
    )
    AddEvent(
        Events.OnDeleteObject,
        function(obj)
            self:OnDeleteObject(obj)
        end
    )
    AddEvent(
        Events.OnProcessSpell,
        function(...)
            self:OnProcessSpell(...)
        end
    )
    AddEvent(
        Events.OnExecuteCastFrame,
        function(...)
            self:OnExecuteCastFrame(...)
        end
    )
    PrintChat("Kaisa loaded")
    self.font = DrawHandler:CreateFont("Calibri", 10)
end

function Kaisa:Menu()
    self.menu = Menu("KaisaEmpyrean", "Kaisa - Empyrean v" .. self.version)
    self.menu:sub("dreamTs", "Target Selector")
    self.menu:checkbox("q", "AutoQ", true, 0x54)
    self.menu:checkbox("w", "Use W only near mouse", true):tooltip(
        "Highly recommended unless playing AP Kaisa with W upgrade"
    )
    self.menu:checkbox("drawW", "Draw W search range", true)
end

function Kaisa:OnDraw()
    DrawHandler:Text(
        DrawHandler.defaultFont,
        Renderer:WorldToScreen(myHero.position),
        self.menu.q:get() and "AutoQ on" or "AutoQ off",
        Color.White
    )
    if self.menu.drawW:get() then
        DrawHandler:Circle3D(pwHud.hudManager.virtualCursorPos, self.w.searchRange, Color.White)
    end
end

function Kaisa:CastQ()
    if myHero.spellbook:CanUseSpell(0) == 0 then
        for i, turret in pairs(self.turrets) do
            local turretObj = turret.object
            if
                turretObj and turretObj.isValid and turretObj.health > 0 and
                    GetDistanceSqr(turretObj) <= turret.range * turret.range
             then
                return
            end
        end
        local myHeroPred = _G.Prediction.GetUnitPosition(myHero, NetClient.ping / 2000 + 0.06)
        for _, enemy in pairs(ObjectManager:GetEnemyHeroes()) do
            if _G.Prediction.IsValidTarget(enemy, 1000) then
                local enemyPred = _G.Prediction.GetUnitPosition(enemy, NetClient.ping / 2000 + 0.06)
                if GetDistanceSqr(myHeroPred, enemyPred) < self.qRange * self.qRange then
                    myHero.spellbook:CastSpell(0, pwHud.hudManager.activeVirtualCursorPos)
                end
            end
        end
    end
end

function Kaisa:W()
    local wTargets, wPreds = self:GetTarget(self.w, true)
    local best1 = nil
    local best2 = nil
    local aa = myHero.characterIntermediate.attackRange + myHero.boundingRadius * 2
    for _, wTarget in pairs(wTargets) do
        if wPreds[wTarget.networkId] then
            local wPred = wPreds[wTarget.networkId]
            if GetDistanceSqr(wPred.castPosition) <= aa * aa then
                best1 = wPred
            elseif
                (not self.menu.w:get() or
                    GetDistanceSqr(pwHud.hudManager.virtualCursorPos, wTarget) <=
                        self.w.searchRange * self.w.searchRange) and
                    wPred.rates["veryslow"]
             then
                best2 = wPred
            end
        end
    end
    if best1 then
        myHero.spellbook:CastSpell(1, best1.castPosition)
    elseif best2 then
        myHero.spellbook:CastSpell(1, best2.castPosition)
    end
end

function Kaisa:ShouldCast()
    for spell, time in pairs(self.LastCasts) do
        if time and RiotClock.time < time + 0.25 + NetClient.ping / 2000 + 0.06 then
            return false
        end
    end
    return true
end

function Kaisa:OnTick()
    if self:ShouldCast() then
        if self.menu.q:get() then
            self:CastQ()
        end
        if Orbwalker:GetMode() == "Combo" then
            self:CastQ()
            if not Orbwalker:IsAttacking() and not (_G.JustEvade and _G.JustEvade.Loaded() and _G.JustEvade.Evading()) then
                self:W()
            end
        end
    end
end

function Kaisa:OnBuffGain(obj, buff)
    if obj == myHero and buff.name == "KaisaE" then
        Orbwalker:BlockAttack(true)
    end
end

function Kaisa:OnBuffLost(obj, buff)
    if obj == myHero and buff.name == "KaisaE" then
        Orbwalker:BlockAttack(false)
    end
end

function Kaisa:OnDeleteObject(obj)
    if self.turrets[obj.networkId] then
        self.turrets[obj.networkId] = nil
    end
end

function Kaisa:OnProcessSpell(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "KaisaQ" then
            self.LastCasts.Q = nil
        end
    end
end

function Kaisa:OnExecuteCastFrame(obj, spell)
    if obj == myHero then
        if spell.spellData.name == "KaisaW" then
            self.LastCasts.W = nil
        end
    end
end

function Kaisa:GetTarget(spell, all, targetFilter, predFilter)
    local units, preds = self.TS:GetTargets(spell, myHero.position, targetFilter, predFilter)
    if all then
        return units, preds
    else
        local target = self.TS.target
        if target then
            return target, preds[target.networkId]
        end
    end
end

return Kaisa
