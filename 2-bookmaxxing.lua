--[[
bookmaxxing: a "Sort by" order for KOReader's file browser.

    Unread books first, shortest to longest.
    Finished books at the back, alphabetically, A to Ö.

"Finished" is KOReader's own book status (long-press a book to set it).

KOReader only learns how long a book is once it has been opened, and for reflowable
formats that number changes with the font size. So the length is measured here, from
the file itself, the first time a book shows up in a folder:

    PDF, DjVu      the real page count, asked of KOReader's own document engine
    MOBI, AZW(3)   the length of the text as stated in the file's header
    EPUB           the size of the text files inside the archive
    plain text     the size of the file

Text lengths are turned into pages at 2300 bytes a page, which is what Kindle page
numbers work out to. Each result is remembered in settings/bookmaxxing.lua and only
measured again if the file changes.

Install: copy this file to koreader/patches/ and restart KOReader.
Remove:  delete it, and pick another order under "Sort by".
--]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local LuaSettings = require("luasettings")

local BYTES_PER_PAGE = 2300

-- Formats where a page is a fixed thing and the document engine can simply be asked.
local PAGED = { pdf = true, djvu = true, djv = true }
-- Formats that are a Mobipocket container.
local MOBI = { mobi = true, azw = true, azw3 = true, prc = true }
-- Formats where the whole file is the text.
local PLAIN = { txt = true, md = true, fb2 = true, html = true, htm = true }

local function u16le(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32le(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function u32be(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function toPages(bytes)
    if not bytes or bytes <= 0 then
        return nil
    end
    return math.max(1, math.floor(bytes / BYTES_PER_PAGE + 0.5))
end

-- The first record of a Mobipocket file starts with a PalmDOC header, which holds the
-- length of the uncompressed text.
local function mobiTextLength(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local head = f:read(86)
    if not head or #head < 86 or head:sub(61, 68) ~= "BOOKMOBI" then
        f:close()
        return nil
    end
    f:seek("set", u32be(head, 79))
    local palmdoc = f:read(8)
    f:close()
    if not palmdoc or #palmdoc < 8 then
        return nil
    end
    return u32be(palmdoc, 5)
end

-- An EPUB is a zip archive. Its directory, at the end of the file, lists every file
-- inside with its uncompressed size, so nothing has to be unpacked.
local function epubTextLength(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local size = f:seek("end")
    local tail_length = math.min(size, 65557)
    f:seek("set", size - tail_length)
    local tail = f:read(tail_length)
    local at, from = nil, 1
    while tail do
        local found = tail:find("PK\5\6", from, true)
        if not found then
            break
        end
        at, from = found, found + 1
    end
    if not at or #tail < at + 19 then
        f:close()
        return nil
    end
    local directory_size, directory_offset = u32le(tail, at + 12), u32le(tail, at + 16)
    f:seek("set", directory_offset)
    local directory = f:read(directory_size)
    f:close()
    if not directory then
        return nil
    end
    local total, p = 0, 1
    while p + 45 <= #directory and directory:sub(p, p + 3) == "PK\1\2" do
        local name_length = u16le(directory, p + 28)
        local name = directory:sub(p + 46, p + 45 + name_length):lower()
        if name:match("%.x?html?$") then
            total = total + u32le(directory, p + 24)
        end
        p = p + 46 + name_length + u16le(directory, p + 30) + u16le(directory, p + 32)
    end
    return total
end

local function documentPageCount(path)
    local doc = DocumentRegistry:openDocument(path)
    if not doc then
        return nil
    end
    local ok, pages = pcall(doc.getPageCount, doc)
    doc:close()
    return ok and tonumber(pages) or nil
end

local function measure(path, size)
    local extension = (path:match("%.([^%./]+)$") or ""):lower()
    if PAGED[extension] then
        return documentPageCount(path)
    elseif MOBI[extension] then
        return toPages(mobiTextLength(path))
    elseif extension == "epub" then
        return toPages(epubTextLength(path))
    elseif PLAIN[extension] then
        return toPages(size)
    end
    return nil
end

local measured = LuaSettings:open(DataStorage:getSettingsDir() .. "/bookmaxxing.lua")
local unsaved = false

local function pagesOf(item)
    local size = item.attr and item.attr.size
    local modified = item.attr and item.attr.modification
    local known = measured:readSetting(item.path)
    if known and known.size == size and known.modified == modified then
        return known.pages or nil
    end
    local ok, pages = pcall(measure, item.path, size)
    pages = ok and pages or nil
    -- A book that could not be measured is remembered too, so it is not tried on every visit.
    measured:saveSetting(item.path, { size = size, modified = modified, pages = pages or false })
    unsaved = true
    return pages
end

-- Swedish alphabetical order: a to z, then å, ä, ö. Those three are swapped for "zza",
-- "zzb" and "zzc", which land after every real word under z and in the right order among
-- themselves, so comparing the keys as plain strings is enough.
-- Other accented letters are filed under their base letter (ü under y, as in Swedish).
local FOLD = {
    ["å"] = "zza", ["Å"] = "zza",
    ["ä"] = "zzb", ["Ä"] = "zzb", ["æ"] = "zzb", ["Æ"] = "zzb",
    ["ö"] = "zzc", ["Ö"] = "zzc", ["ø"] = "zzc", ["Ø"] = "zzc",
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Õ"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u",
    ["ü"] = "y", ["Ü"] = "y", ["ý"] = "y", ["Ý"] = "y",
    ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n", ["Ñ"] = "n",
}

local function swedishKey(name)
    -- Every letter above is two bytes in UTF-8, the first of them 0xC3.
    local key = name:gsub("\195[\128-\191]", FOLD)
    return key:lower()
end

BookList.collates.bookmaxxing = {
    text = "bookmaxxing",
    menu_order = 5,
    can_collate_mixed = false,
    init_sort_func = function()
        -- Runs once per folder, after every book in it has been looked at.
        if unsaved then
            unsaved = false
            pcall(measured.flush, measured)
        end
        return function(a, b)
            local a_done, b_done = a.bm_finished == true, b.bm_finished == true
            if a_done ~= b_done then
                return b_done
            end
            if not a_done then
                local a_pages, b_pages = a.bm_pages or math.huge, b.bm_pages or math.huge
                if a_pages ~= b_pages then
                    return a_pages < b_pages
                end
            end
            local a_key = a.bm_key or swedishKey(a.text or "")
            local b_key = b.bm_key or swedishKey(b.text or "")
            if a_key ~= b_key then
                return a_key < b_key
            end
            return (a.text or "") < (b.text or "")
        end
    end,
    item_func = function(item)
        local info = BookList.getBookInfo(item.path)
        item.opened = info.been_opened
        item.bm_finished = info.been_opened and info.status == "complete" or false
        item.bm_key = swedishKey(item.text)
        local ok, pages = pcall(pagesOf, item)
        item.bm_pages = ok and pages or info.pages
    end,
    mandatory_func = function(item)
        if item.bm_finished then
            return "read"
        end
        return item.bm_pages and (item.bm_pages .. " p") or "–"
    end,
}
