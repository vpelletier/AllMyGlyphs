--[[
Copyright (c) 2013-2014 Vincent Pelletier

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Note:
    This AddOn's source code is specifically designed to work with
    World of Warcraft's interpreted AddOn system.
    You have an implicit license to use this AddOn with these facilities
    since that is its designated purpose as per:
    http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
--]]

-- lua
local select = select
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local tsort = table.sort
local ssub = string.sub

-- WoW API
-- GLOBALS: GetNumGlyphs, GetGlyphInfo, UnitName, UnitClass, GetRealmName
-- GLOBALS: strlen, strlower
-- GLOBALS: ERR_FRIEND_NOT_FOUND, SUCCESS

-- LibStub
-- GLOBALS: LibStub

-- This addon
-- GLOBALS: AllMyGlyphs

local GLYPH_KEY = "glyph"
local CLASS_KEY = "class"

local function map_concat(table, sep)
    local result
    for _, value in pairs(table) do
        if result == nil then
            result = value
        else
            result = result..sep..value
        end
    end
    return result
end

local function setdefault(table, key, default)
    local result = table[key]
    if result == nil then
        result = default
        table[key] = default
    end
    return result
end

AllMyGlyphs = LibStub("AceAddon-3.0"):NewAddon("AllMyGlyphs", "AceConsole-3.0",
  "AceHook-3.0", "AceEvent-3.0")

function AllMyGlyphs:OnInitialize()
    local base_db = LibStub("AceDB-3.0"):New("AllMyGlyphsDB")
    -- Per-realm, in an attempt to separate test realms from live (in case
    -- there are glyph changes between them)
    local link_db = setdefault(setdefault(base_db, "realm", {}), "link_db", {})
    local global_db = setdefault(base_db, "global", {})
    local toon_db = setdefault(global_db, "toon_db", {})
    local class_caption = setdefault(global_db, "class_caption", {})
    local current_playerName = UnitName("player").."@"..GetRealmName()
    local current_toon_class_caption, _, current_toon_class = UnitClass("player")
    local current_toon_db = toon_db[current_playerName]
    class_caption[current_toon_class] = current_toon_class_caption
    if current_toon_db == nil or current_toon_db[CLASS_KEY] ~= current_toon_class then
        current_toon_db = {
            [CLASS_KEY] = current_toon_class,
            [GLYPH_KEY] = {},
        }
        toon_db[current_playerName] = current_toon_db
    end
    self.toon_db = toon_db
    self.current_toon_db = current_toon_db[GLYPH_KEY]
    self.class_caption = class_caption
    self.link_db = link_db
    self.need_update = true
    local function updateGlyphs() self:updateGlyphs() end
    self:RegisterEvent("PLAYER_TALENT_UPDATE", updateGlyphs)
    self:RegisterEvent("USE_GLYPH", updateGlyphs)
    self:RegisterChatCommand("amg", function(input, editBox) self:dump(input, editBox) end)
    self:RegisterChatCommand("amgForget", function(input, editBox) self:forget(input, editBox) end)
end

function AllMyGlyphs:updateReverse()
    local reverse_toon_db = {}
    local class_glyphs = {}
    for toon_ident, toon_glyph_map in pairs(self.toon_db) do
        local current_class_glyphs = setdefault(class_glyphs, toon_glyph_map[CLASS_KEY], {})
        for glyph_id, known in pairs(toon_glyph_map[GLYPH_KEY]) do
            tinsert(current_class_glyphs, glyph_id)
            local reverse_db = setdefault(reverse_toon_db, glyph_id, {})
            if not known then
                -- any value but nil would do
                reverse_db[toon_ident] = 1
            end
        end
    end
    local link_db = self.link_db
    local function comp(a, b) return link_db[a] < link_db[b] end
    for _, current_class_glyphs in pairs(class_glyphs) do
        tsort(current_class_glyphs, comp)
    end
    self.reverse_toon_db = reverse_toon_db
    self.class_glyphs = class_glyphs
end

function AllMyGlyphs:dump(input, editBox)
    local class
    input = strlower(input)
    local input_len = strlen(input)
    for current_class, caption in pairs(self.class_caption) do
        if strlower(ssub(caption, 1, input_len)) == input then
            if class == nil then
                class = current_class
            else
                class = nil
                break
            end
        end
    end
    if class == nil then
        self:Print(map_concat(self.class_caption, ", "))
        return
    end
    if self.need_update then
        self:updateReverse()
        self.need_update = false
    end
    local glyph_list = self.class_glyphs[class]
    self:Print(self.class_caption[class])
    for _, glyph_id in ipairs(glyph_list) do
        local toons = ""
        for toon_ident, _ in pairs(self.reverse_toon_db[glyph_id]) do
            if toons ~= "" then
                toons = toons..", "
            end
            toons = toons..toon_ident
        end
        if toons ~= "" then
            self:Print("  "..self.link_db[glyph_id]..": "..toons)
        end
    end
end

function AllMyGlyphs:forget(input, editBox)
    if input and input:trim() then
        local exists = self.toon_db[input]
        if exists == nil then
            self:Print(ERR_FRIEND_NOT_FOUND)
            return
        end
        self.toon_db[input] = nil
        self.need_update = true
        self:Print(SUCCESS)
        return
    end
    for toon_ident, _ in pairs(self.toon_db) do
        self.toon_db[toon_ident] = nil
    end
    for glyph_id, _ in pairs(self.current_toon_db[GLYPH_KEY]) do
        self.current_toon_db[glyph_id] = nil
    end
    self.need_update = true
    self:Print(SUCCESS)
end

function AllMyGlyphs:updateGlyphs()
    local current_toon_glyphs = self.current_toon_db
    local _, name, known, glyph_id, link
    for index = 1, GetNumGlyphs() do
        name, _, known, _, glyph_id, link, _ = GetGlyphInfo(index);
        if name ~= "header" then
            current_toon_glyphs[glyph_id] = known
            self.link_db[glyph_id] = link
        end
    end
    self.need_update = true
end
