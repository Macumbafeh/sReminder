--------------------------------------------------------------------------------
-- sReminder (c) 2013 by Siarkowy
-- Released under the terms of BSD 2-Clause license.
--------------------------------------------------------------------------------

sReminder = LibStub("AceAddon-3.0"):NewAddon(
    "sReminder",

    -- embeds:
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0",
    "LibFuBarPlugin-Mod-3.0"
)

local sReminder = sReminder

local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local SecondsToTime = SecondsToTime
local abs = abs
local assert = assert
local format = format
local strsub = strsub
local tonumber = tonumber
local unpack = unpack

local SECOND =  1
local MINUTE = 60 * SECOND
local HOUR   = 60 * MINUTE
local DAY    = 24 * HOUR
local WEEK   =  7 * DAY

sReminder.intervals = {
    3 * DAY, 2 * DAY, 1 * DAY,
    12 * HOUR, 6 * HOUR, 3 * HOUR, 2 * HOUR, 1 * HOUR,
    45 * MINUTE, 30 * MINUTE, 15 * MINUTE, 10 * MINUTE,
    5 * MINUTE, 2 * MINUTE, 1 * MINUTE, 30 * SECOND,
    0 -- at this point timer will be deleted
}

sReminder.cooldowns = {                 -- [spell] = cooldown
    -- Alchemy
    ["Transmute"]       = 20 * HOUR,    -- one cooldown for all transmutes

    -- Jewelcrafting
    ["Brilliant Glass"] = 20 * HOUR,

    -- Tailoring
    ["Primal Mooncloth"] = 92 * HOUR,   -- 3d 20h
    ["Shadowcloth"]     = 92 * HOUR,    -- 3d 20h
    ["Spellcloth"]      = 92 * HOUR,    -- 3d 20h
}

local cooldowns = sReminder.cooldowns
local intervals = sReminder.intervals

local defaults = {
    profile = {
        timers = {
            -- { character, timestamp, label, reminded },
            -- ...
        }
    }
}

-- Utils -----------------------------------------------------------------------

--- Prints formatted text into the chat frame.
-- @param ... (list) Format and other args list.
function sReminder:Echo(...)
    DEFAULT_CHAT_FRAME:AddMessage(format(...))
end

--- Returns formatted label for the timer.
-- @param timer (array) Timer object.
-- @param dot (boolean) If the formatted timer should end with a dot.
-- @return (string) Timer label.
function sReminder.GetFormattedTimer(timer, dot)
    local character, timestamp, label, reminded = unpack(assert(timer))
    return format("%s: %s %s%s", character, label, sReminder.SecondsToTime(timestamp - time()), dot and "." or "")
end

--- Returns interval following the one given.
-- @param int (number) Interval value.
-- @return (number) Next interval value.
function sReminder.GetNextInterval(int)
    for _, n in ipairs(intervals) do
        if int > n then return n end
    end
end

--- Returns readable time string.
-- @param int (number) Interval value.
-- @return (string) Time string.
function sReminder.SecondsToTime(int)
    local string = SecondsToTime(abs(int))
    return format("%s%s%s", int > 0 and "in " or int <= 0 and "expired " or "", int ~= 0 and string or "just now", int < 0 and " ago" or "")
end

--- Returns class colored unit name.
-- @param unit (string) UnitId.
-- @return (string) Colored name.
function sReminder.UnitColoredName(unit)
    local col = RAID_CLASS_COLORS[select(2, UnitClass(unit))]
    return col and format("|cff%02x%02x%02x%s|r", col.r * 255, col.g * 255, col.b * 255, UnitName(unit)) or unit
end

-- Some speed-up locals
local GetFormattedTimer = sReminder.GetFormattedTimer
local GetNextInterval = sReminder.GetNextInterval
local UnitColoredName = sReminder.UnitColoredName

-- Core ------------------------------------------------------------------------

function sReminder:OnEnable()
    self:ScheduleRepeatingTimer("CheckTimers", 1)
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

--- Checks if player has triggered any trade skill cooldown.
function sReminder:UNIT_SPELLCAST_SUCCEEDED(event, unit, spell, rank)
    if unit ~= "player" then return end

    if strsub(spell, 1, 10) == "Transmute:" and spell ~= "Transmute: Arcanite" then
        self:NewTimer("player", time() + cooldowns.Transmute, "Transmutation")

    elseif cooldowns[spell] then
        self:NewTimer("player", time() + cooldowns[spell], spell)
    end
end

function sReminder:VARIABLES_LOADED()
    self:CheckTimers(true)
end

--- Manages deletion, interval change and chat frame printing of timers.
-- Also updates FuBar tooltip if timers are present.
-- @param first (boolean) If true, all timers are printed to chat frame.
function sReminder:CheckTimers(first)
    local interval, reminded, update, nextintv

    for i, timer in ipairs(self.timers) do
        update = true
        interval = timer[2] - time()
        reminded = timer[4]
        nextintv = GetNextInterval(interval)

        if interval <= 0 then
            self:Print(GetFormattedTimer(timer, true))
            tremove(self.timers, i)

        elseif timer[4] ~= nextintv then
            timer[4] = nextintv
            self:Print(GetFormattedTimer(timer, true))

        elseif first then
            self:Print(GetFormattedTimer(timer, true))
        end
    end

    if update then
        self:UpdateFuBarPlugin()
    end
end

--- Deletes a timer.
-- @param char (string|nil) Optional character name.
-- @param label (string) Timer title.
-- @return (boolean) If any timer was deleted.
function sReminder:DeleteTimer(char, label)
    for i, timer in ipairs(self.timers) do
        if (not char or timer[1]:match(char)) and timer[3] == label then
            tremove(self.timers, i)
            self:UpdateFuBarPlugin()
            return true
        end
    end

    return false
end

local sortfunc = function(a, b) return a[2] < b[2] end

--- Creates a timer.
-- @param char (string) UnitId or character name.
-- @param timestamp (number) Timer end timestamp.
-- @param label (string) Descriptive title.
-- @return (array) Timer object.
function sReminder:NewTimer(char, timestamp, label)
    local timer = { UnitColoredName(char), timestamp, label }

    tinsert(self.timers, timer)
    sort(self.timers, sortfunc)
    self:CheckTimers()

    return timer
end

-- FuBar functions -------------------------------------------------------------

--- Updates the title of FuBar plugin.
function sReminder:UpdateFuBarText()
    local timer = self.timers[1]

    self:SetFuBarText(timer and GetFormattedTimer(timer) or self.name)
end

--- Feeds GameTooltip with timer information.
function sReminder:OnUpdateFuBarTooltip()
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self.name)

    if #self.timers > 0 then
        local interval
        GameTooltip:AddDoubleLine("Timer", "Description", 1, 1, 0, 1, 1, 0)
        for i, timer in ipairs(self.timers) do
            interval = timer[2] - time()
            GameTooltip:AddDoubleLine(
                format(
                    "%s (%s%s)",
                    date("%Y-%d-%m %H:%M", timer[2]),
                    SecondsToTime(abs(interval)),
                    interval < 0 and " ago" or ""
                ),
                format("%1$s: %3$s", unpack(timer)),
                1, 1, 1,
                1, 1, 1
            )
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hint: Remove timer with /unremind command.", 0, 1, 0)

    else
        GameTooltip:AddLine("There are no running timers to show.", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hint: Add timer with /remind command.", 0, 1, 0)
    end

    -- GameTooltip:Show()
end

-- Initialization --------------------------------------------------------------

function sReminder:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("sReminderDB", defaults, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", function(event, db, newprofile) self.timers = db.profile.timers end)
    self.timers = self.db.profile.timers

    -- Slash command staff
    self:RegisterChatCommand("remind", "OnSlash__remind")
    self:RegisterChatCommand("unremind", "OnSlash__unremind")

    -- FuBar config
    self:SetFuBarOption("cannotDetachTooltip", true)
    self:SetFuBarOption("configType", "none")
    self:SetFuBarOption("defaultPosition", "RIGHT")
    self:SetFuBarOption("hasNoColor", true)
    self:SetFuBarOption("hideWithoutStandby", true)
    self:SetFuBarOption("iconPath", [[Interface\Icons\INV_MISC_IDOL_05]])
    self:SetFuBarOption("tooltipType", "GameTooltip")

    self:RegisterEvent("VARIABLES_LOADED")
end

-- Slash command ---------------------------------------------------------------

--- Interval multipliers
local multipliers = {
    w = WEEK,
    d = DAY,
    h = HOUR,
    m = MINUTE,
    s = SECOND,
}

--- Converts interval string to numeric interval.
-- @param string (string) Interval string.
-- @return (number) Numeric interval value.
local function StringToInterval(string)
    local interval = 0

    for num, mul in string:lower():gmatch("(%d+)([wdhms])") do
        interval = interval + num * multipliers[mul]
    end

    return interval
end

--- Handles /remind slash command.
function sReminder:OnSlash__remind(param)
    local minus, timestring, label = param:match("^(%-?)([0-9wdhms]+)%s+(.+)$")

    if not timestring or not label then
        self:Print("Usage: /remind <interval> <label>");
        self:Echo("   <interval> is a string in format of '1w3d20h15m6s'.");
        self:Echo("   <label> is a descriptional title for the timer.");
        self:Echo("At least one <digit>[wdhms] part of <interval> must be given.");
        self:Echo("See also /unremind.");

        return
    end

    local interval = StringToInterval(timestring)
    local timer = self:NewTimer("player", time() + interval * (minus == "" and 1 or -1), label)
end

--- Handles /unremind slash command.
function sReminder:OnSlash__unremind(param)
    if not param or param == "" then
        self:Print("Usage: /unremind [ @<character> ] <label>")
        self:Echo("   <character> is an optional character name with @ in front of it.")
        self:Echo("   <label> is the title of the timer to be deleted.")
        self:Echo("See also /remind.")

        return
    end

    local char
    local function SetChar(m) char = m; return "" end
    local label = param:gsub("@(%S+)", SetChar):trim()

    self:Print(self:DeleteTimer(char, label) and format("Timer %s deleted.", label)
        or format("Timer %s not found.", label))
end
