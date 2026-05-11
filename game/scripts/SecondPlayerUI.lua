--
-- Thin compatibility shim around CoopPlayerUi for slot 2. All UI logic now
-- lives in CoopPlayerUi.lua, parameterized on a position config; this file
-- exposes the original SecondPlayerUi.* method surface for existing call
-- sites (UIHooks, DamageHooks, GamemodeInit, RunHooks) so they keep working
-- unchanged. The P2 instance uses the bottom-right corner layout that
-- matches the original screen positions byte-for-byte.
--

---@type CoopPlayerUi
local CoopPlayerUi = ModRequire "CoopPlayerUi.lua"

---@class SecondPlayerUi
local SecondPlayerUi = {}

local cachedInstance

local function GetInstance()
    if cachedInstance == nil then
        cachedInstance = CoopPlayerUi.Get(2)
            or CoopPlayerUi.Create(2, CoopPlayerUi.LayoutForCorner("BR"))
        -- Expose the same ScreenAnchors table the original file did; UIHooks
        -- still reads SecondPlayerUi.ScreenAnchors directly in a few spots.
        SecondPlayerUi.ScreenAnchors = cachedInstance.ScreenAnchors
    end
    return cachedInstance
end

-- Eagerly create on file load so SecondPlayerUi.ScreenAnchors is non-nil for
-- early call sites (e.g. ammo-bar indexing in DamageHooks.OnHit before any
-- show/update has fired yet).
GetInstance()

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
