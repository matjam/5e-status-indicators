-- MIT License
-- -----------
--
-- Copyright (c) 2020 Nathan Ollerenshaw
--
-- Permission is hereby granted, free of charge, to any person
-- obtaining a copy of this software and associated documentation
-- files (the "Software"), to deal in the Software without
-- restriction, including without limitation the rights to use,
-- copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
-- HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
-- WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
-- OTHER DEALINGS IN THE SOFTWARE.

local originalApplySave = nil
local originalOnDesktopInit = nil

local failTokenName = "overlay_save_failure"
local successTokenName = "overlay_save_success"
local halfTokenName = "overlay_save_half"

local tokenNames = {
    critical = "overlay_critical",
    heavy = "overlay_heavy",
    moderate = "overlay_moderate"
}

local deadTokenName = "overlay_dead"
local moderateTokenName = "overlay_"

local saveStatusIndicatorName = "save_status_indicator"
local healthStatusIndicatorName = "health_status_indicator"
local deathStatusIndicatorName = "death_status_indicator"

function onInit()
    -- By doing this we can be sure that if some other extension also wants to override or
    -- hook into this function, we won't break what they're doing.
    originalApplySave = ActionSave.applySave
    ActionSave.applySave = customApplySave

    originalOnDesktopInit = Interface.onDesktopInit
    Interface.onDesktopInit = customOnDesktopInit

    CombatManager.setCustomTurnStart(turnStart)
    CombatManager.addCombatantFieldChangeHandler("wounds", "onUpdate", healthStatus)
    CombatManager.addCombatantFieldChangeHandler("tokenrefid", "onUpdate", healthStatus)

    OptionsManager.registerOption2(
        "MJSI_ENABLED",
        false,
        "option_header_matjams_status_indicators",
        "option_label_MJSI_ENABLED",
        "option_entry_cycler",
        {labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on"}
    )
    OptionsManager.registerOption2(
        "MJSI_SPATTER_ENABLED",
        false,
        "option_header_matjams_status_indicators",
        "option_label_MJSI_SPATTER_ENABLED",
        "option_entry_cycler",
        {labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on"}
    )
    OptionsManager.registerOption2(
        "MJSI_SKULLS_ENABLED",
        false,
        "option_header_matjams_status_indicators",
        "option_label_MJSI_SKULLS_ENABLED",
        "option_entry_cycler",
        {labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on"}
    )

    DB.addHandler("options.MJSI_ENABLED", "onUpdate", updateHealthIndicators)
    DB.addHandler("options.MJSI_SPATTER_ENABLED", "onUpdate", updateHealthIndicators)
    DB.addHandler("options.MJSI_SKULLS_ENABLED", "onUpdate", updateHealthIndicators)
end

function customOnDesktopInit()
    if originalOnDesktopInit ~= nil then
        originalOnDesktopInit()
    end

    updateHealthIndicators()
end

function updateHealthIndicators()
    -- update the spatter/blood if necessary
    for _, node in pairs(CombatManager.getCombatantNodes()) do
        healthStatus(node.getChild("wounds"))
    end

    -- kill the save indicators
    if not OptionsManager.isOption("MJSI_ENABLED", "on") then
        clearStatusIndicators(saveStatusIndicatorName)
    end
end

function customApplySave(rSource, rOrigin, rAction, sUser)
    originalApplySave(rSource, rOrigin, rAction, sUser)

    local tokenCT = CombatManager.getTokenFromCT(rSource.sCTNode)
    if not (tokenCT) then
        return
    end

    deleteBitmapWithName(tokenCT, saveStatusIndicatorName)

    if OptionsManager.isOption("MJSI_ENABLED", "on") == false then
        return
    end

    local half_on_save = string.match(string.lower(rAction.sSaveDesc), "half on save")

    if (rAction.nTotal >= rAction.nTarget and not half_on_save) then
        -- Full save
        applyBitmapToToken(tokenCT, saveStatusIndicatorName, successTokenName)
    elseif (rAction.nTotal >= rAction.nTarget and half_on_save) then
        -- half save
        applyBitmapToToken(tokenCT, saveStatusIndicatorName, halfTokenName)
    else
        -- failed save
        applyBitmapToToken(tokenCT, saveStatusIndicatorName, failTokenName)
    end
end

function healthStatus(nodeField)
    local nodeCT = nodeField.getParent()
    local tokenCT = CombatManager.getTokenFromCT(nodeCT)
    local pDmg, pStatus, sColor = TokenManager2.getHealthInfo(nodeCT)

    deleteBitmapWithName(tokenCT, healthStatusIndicatorName)
    deleteBitmapWithName(tokenCT, deathStatusIndicatorName)

    local healthStatus = string.lower(pStatus)
    local dead = false
    if healthStatus == "dead" or healthStatus == "dying" then
        dead = true
        healthStatus = "critical"
    end

    if tokenNames[healthStatus] ~= nil and OptionsManager.isOption("MJSI_SPATTER_ENABLED", "on") then
        -- throw a little blood on there
        applyBitmapToToken(tokenCT, healthStatusIndicatorName, tokenNames[healthStatus])
    end

    if dead and OptionsManager.isOption("MJSI_SKULLS_ENABLED", "on") then
        -- throw on a skull
        applyBitmapToToken(tokenCT, deathStatusIndicatorName, deadTokenName)
    end
end

function deleteBitmapWithName(tokenCT, bitmapName)
    if tokenCT == nil then
        return
    end

    local statusWidget = tokenCT.findWidget(bitmapName)
    if statusWidget then
        statusWidget.destroy()
    end
end

function applyBitmapToToken(tokenCT, bitmapName, tokenName)
    if tokenName == nil or tokenCT == nil then
        return
    end

    local nWidth, nHeight = tokenCT.getSize()

    statusWidget = tokenCT.addBitmapWidget(tokenName)
    statusWidget.setBitmap(tokenName)
    statusWidget.setName(bitmapName)
    statusWidget.setSize(nWidth, nHeight)
    statusWidget.setVisible(true)
end

-- Every turn, we want to clear any success/fail tokens we have set.
function turnStart(nodeCT)
    clearStatusIndicators(saveStatusIndicatorName)
end

function clearStatusIndicators(name)
    for _, node in pairs(CombatManager.getCombatantNodes()) do
        local tokenCT = CombatManager.getTokenFromCT(node)
        if tokenCT then
            local statusWidget = tokenCT.findWidget(name)

            if statusWidget then
                statusWidget.destroy()
            end
        end
    end
end
