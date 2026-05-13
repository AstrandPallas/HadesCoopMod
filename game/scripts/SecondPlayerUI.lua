--
-- Thin compatibility shim around CoopPlayerUi for slot 2. All UI logic now
-- lives in CoopPlayerUi.lua, parameterized on a position config; this file
-- exposes the original SecondPlayerUi.* method surface for existing call
-- sites (UIHooks, DamageHooks, GamemodeInit, RunHooks) so they keep working
-- unchanged. The P2 instance uses the bottom-row slot layout sized for the
-- active player count — in 2P this collapses to the legacy BR position
-- byte-identical; in 3P/4P P2 occupies a middle slot.
--

---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "CoopPlayerUi.lua"
---@type CoopPlayers
local CoopPlayers = ModRequire "CoopPlayers.lua"

---@class SecondPlayerUi
local SecondPlayerUi = {}

-- Pre-populated with an empty table so early `SecondPlayerUi.ScreenAnchors.X`
-- reads from UIHooks closures don't nil-index. Instance creation is deferred
-- to first use because LayoutForBottomSlot references ScreenWidth, which the
-- engine hasn't defined yet at module-load time.
SecondPlayerUi.ScreenAnchors = {}

local cachedInstance

local function GetInstance()
    if cachedInstance == nil then
        cachedInstance = CoopPlayerUi.Get(2)
        if cachedInstance == nil then
            cachedInstance = CoopPlayerUi.Create(2,
                CoopPlayerUi.LayoutForBottomSlot(2, CoopPlayers.GetPlayersCount()))
        end
        -- Share storage with the placeholder ScreenAnchors so any references
        -- captured earlier still see live data: copy any existing entries
        -- across, then point the instance at our table.
        for k, v in pairs(cachedInstance.ScreenAnchors) do
            SecondPlayerUi.ScreenAnchors[k] = v
        end
        cachedInstance.ScreenAnchors = SecondPlayerUi.ScreenAnchors
    end
    return cachedInstance
end

-- Forwarding methods. Each just delegates to the cached P2 instance.
function SecondPlayerUi.ShowHealthUI()                 GetInstance():ShowHealthUI() end
function SecondPlayerUi.UpdateHealthUI()               GetInstance():UpdateHealthUI() end
function SecondPlayerUi.UpdateRallyHealthUI()          GetInstance():UpdateRallyHealthUI() end
function SecondPlayerUi.HideHealthUI()                 GetInstance():HideHealthUI() end
function SecondPlayerUi.DestroyHealthUI()              GetInstance():DestroyHealthUI() end
function SecondPlayerUi.UpdateLifePips()               GetInstance():UpdateLifePips() end
function SecondPlayerUi.RecreateLifePips()             GetInstance():RecreateLifePips() end
function SecondPlayerUi.ShowAmmoUI()                   GetInstance():ShowAmmoUI() end
function SecondPlayerUi.UpdateAmmoUI()                 GetInstance():UpdateAmmoUI() end
function SecondPlayerUi.HideAmmoUI()                   GetInstance():HideAmmoUI() end
function SecondPlayerUi.StartAmmoReloadPresentation(d) GetInstance():StartAmmoReloadPresentation(d) end
function SecondPlayerUi.EndAmmoReloadPresentation()    GetInstance():EndAmmoReloadPresentation() end
function SecondPlayerUi.DestroyAmmoUI()                GetInstance():DestroyAmmoUI() end
function SecondPlayerUi.ShowGunUI(gunData)             GetInstance():ShowGunUI(gunData) end
function SecondPlayerUi.UpdateGunUI(triggerArgs)       GetInstance():UpdateGunUI(triggerArgs) end
function SecondPlayerUi.HideGunUI()                    GetInstance():HideGunUI() end
function SecondPlayerUi.DestroyGunUI()                 GetInstance():DestroyGunUI() end
function SecondPlayerUi.ShowSuperMeter()               GetInstance():ShowSuperMeter() end
function SecondPlayerUi.HideSuperMeter()               GetInstance():HideSuperMeter() end
function SecondPlayerUi.DestroySuperMeter()            GetInstance():DestroySuperMeter() end
function SecondPlayerUi.UpdateSuperUIComponent(i, f)   GetInstance():UpdateSuperUIComponent(i, f) end
function SecondPlayerUi.UpdateSuperMeterUIReal()       GetInstance():UpdateSuperMeterUIReal() end
function SecondPlayerUi.Refresh()                      GetInstance():Refresh() end

return SecondPlayerUi
