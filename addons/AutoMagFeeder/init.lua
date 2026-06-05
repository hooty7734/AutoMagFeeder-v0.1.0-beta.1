-- ========================================================================== --
-- PSOBB Mod Addon: AutoMagFeeder (Core Initialization & Execution Engine)    --
-- File: init.lua                                                             --
-- ========================================================================== --

-- === FRAMEWORK DEPENDENCIES ===
local core_mainmenu = require("core_mainmenu")
local lib_helpers = require("solylib.helpers")
local lib_items = require("solylib.items.items")
local lib_characters = require("solylib.characters")
local ffi = require("ffi")
local ImGui = require("imgui")
local item_data = require("solylib.items.items_list")
local item_table = item_data.t

-- Maps exact item name strings to correct PSOBB flat hex codes
local ITEM_NAME_TO_ID = {
    ["Monomate"] = "0x030000",
    ["Monofluid"] = "0x030100",
    ["Dimate"] = "0x030001",
    ["Difluid"] = "0x030101",
    ["Trimate"] = "0x030002",
    ["Trifluid"] = "0x030102",
    ["Sol Atomizer"] = "0x030300",
    ["Moon Atomizer"] = "0x030400",
    ["Star Atomizer"] = "0x030500",
    ["Antidote"] = "0x030600",
    ["Antiparalysis"] = "0x030601",

    -- Mag Cells & Aliases
    ["Cell of MAG 213"] = "0x030C01",
    ["Cell of MAG 502"] = "0x030C00",
    ["Heart of Chao"] = "0x030C05",
    ["Heart of RoboChao"] = "0x030C02",
    ["Parts of RoboChao"] = "0x030C02",
    ["Heart of Pian"] = "0x030C04",
    ["Heart of Opa Opa"] = "0x030C03",
    ["Heart of Chu Chu"] = "0x030E0B",
    ["Heart of Kapu Kapu"] = "0x030E26",
    ["Heart of KAPU KAPU"] = "0x030E26",
    ["Heart of Angel's"] = "0x030E0D",
    ["Heart of Angel"] = "0x030E0D",
    ["Heart of Devil's"] = "0x030E0E",
    ["Heart of Devil"] = "0x030E0E",
    ["Panter's Spirit"] = "0x030E10",
    ["Panther's Spirit"] = "0x030E10",
    ["Kit of Hamburger"] = "0x030E0F",
    ["Kit of Mark III"] = "0x030E11",
    ["Kit of MARK3"] = "0x030E11",
    ["Kit of Master System"] = "0x030E12",
    ["Kit of MASTER SYSTEM"] = "0x030E12",
    ["Kit of Genesis"] = "0x030E13",
    ["Kit of GENESIS"] = "0x030E13",
    ["Kit of Saturn"] = "0x030E14",
    ["Kit of SEGA SATURN"] = "0x030E14",
    ["Kit of Dreamcast"] = "0x030E15",
    ["Kit of DREAMCAST"] = "0x030E15",
    ["Heart of YN-1107"] = "0x031810",
    ["Heart of YN-0117"] = "0x031810",
    ["Liberta Kit"] = "0x03180A",
    ["D-Photon Core"] = "0x031809",
    ["Tablet"] = "0x031800",
    ["Heart of Morolian"] = "0x031806",
    ["Pioneer Parts"] = "0x031804",
    ["Amitie's Meno"] = "0x031805",
    ["Amitie's Memo"] = "0x031805",
    ["Rappy Beak"] = "0x031807",
    ["Rappy's Beak"] = "0x031807",
    ["Heaven Striket Coat"] = "0x031803",
    ["Heaven Striker Coat"] = "0x031803",
    ["Dragon Scale"] = "0x031802",
    ["Yahoo! Engine"] = "0x031808",
    ["Yahoo!'s engine"] = "0x031808",
    ["Ultima!'s engine"] = "0x031808",
    ["Ultima's Engine"] = "0x031808",
}

-- === DEBUG LOGGING ENGINE ===
local debug_logs = {}
local function debug_log(msg)
    local time_str = os.date("%H:%M:%S")
    local log_entry = string.format("[%s] %s", time_str, msg)
    table.insert(debug_logs, 1, log_entry)
    if #debug_logs > 50 then table.remove(debug_logs) end -- Keep last 50 logs
    print("[AutoMagFeeder] " .. msg)
end

-- === C/C++ FFI DEFINITIONS ===
-- This must come AFTER local ffi = require("ffi")
ffi.cdef[[
    void keybd_event(unsigned char bVk, unsigned char bScan, unsigned long dwFlags, unsigned long dwExtraInfo);
    unsigned int MapVirtualKeyA(unsigned int uCode, unsigned int uMapType);

    void* GetForegroundWindow();
    unsigned long GetWindowThreadProcessId(void* hWnd, unsigned long* lpdwProcessId);
    unsigned long GetCurrentProcessId();

    short GetAsyncKeyState(int vKey);
]]

-- === HARDWARE TIMING CONSTANTS ===
local KEY_PRESS_HOLD_MS = 100  -- Duration to hold key down (AHK 100ms)
local KEY_DELAY_MS      = 400  -- Wait between key presses (AHK 400ms)

-- === KEY-INPUT CONSTANTS ===
-- PSOBB reads the VIRTUAL key, so we inject by VK and leave bScan = 0. keybd_event
-- only uses a scan code when KEYEVENTF_SCANCODE is set (which we don't need) -- so a
-- VK-only path works. The one flag that matters is KEYEVENTF_EXTENDEDKEY for arrows.
-- (If a server ever needed raw DirectInput scan codes, that's the fallback: set
-- KEYEVENTF_SCANCODE, pass bVk = 0, and supply the real scan code.)
local VK_RETURN = 0x0D
local VK_UP     = 0x26
local VK_DOWN   = 0x28
local VK_ESCAPE = 0x1B  -- backs out one menu level
local VK_F4     = 0x73  -- opens the Mag menu
local VK_F12    = 0x7B  -- closes all open windows/menus

local KEYEVENTF_KEYUP       = 0x0002
local KEYEVENTF_EXTENDEDKEY = 0x0001  -- required for directional (arrow) keys

-- Virtual keys that must carry the extended-key flag (the arrow keys).
local EXTENDED_KEYS = {
    [VK_UP]   = true,
    [VK_DOWN] = true,
}

-- Key names lookup table for diagnostics
local KEY_NAMES = {
    [VK_RETURN] = "ENTER",
    [VK_UP]     = "UP",
    [VK_DOWN]   = "DOWN",
    [VK_ESCAPE] = "ESC",
    [VK_F4]     = "F4",
    [VK_F12]    = "F12",
}

-- Press / release a virtual key (mapping the virtual key to a hardware scan code
-- so that DirectInput-based game clients register the input correctly).
local function key_down(vk)
    local sc = ffi.C.MapVirtualKeyA(vk, 0)
    local flags = EXTENDED_KEYS[vk] and KEYEVENTF_EXTENDEDKEY or 0
    ffi.C.keybd_event(vk, sc, flags, 0)
    debug_log(string.format("Key Down: %s (VK: 0x%02X, SC: 0x%02X)", KEY_NAMES[vk] or "UNK", vk, sc))
end
local function key_up(vk)
    local sc = ffi.C.MapVirtualKeyA(vk, 0)
    local flags = (EXTENDED_KEYS[vk] and KEYEVENTF_EXTENDEDKEY or 0) + KEYEVENTF_KEYUP
    ffi.C.keybd_event(vk, sc, flags, 0)
    debug_log(string.format("Key Up  : %s (VK: 0x%02X, SC: 0x%02X)", KEY_NAMES[vk] or "UNK", vk, sc))
end

-- Shortest cursor path to a 0-based target in a wrapping list of `count` items
-- (the menu cursor starts at the top and wraps top<->bottom). Returns a list of
-- VK_DOWN / VK_UP presses -- going Up wraps from the top straight to the bottom.
local function nav_presses(offset, count)
    local presses = {}
    if not offset or not count or count <= 0 then return presses end
    if offset * 2 <= count then
        for _ = 1, offset do presses[#presses + 1] = VK_DOWN end
    else
        for _ = 1, (count - offset) do presses[#presses + 1] = VK_UP end
    end
    return presses
end

local SECTION_IDS = {
    [0] = "Viridia", [1] = "Greenill", [2] = "Skyly", [3] = "Bluefull",
    [4] = "Purplenum", [5] = "Pinkal", [6] = "Redria", [7] = "Oran",
    [8] = "Yellowboze", [9] = "Whitill"
}

-- === NATIVE OS FOCUS CHECKER ===
local function is_game_window_active()
    local fg_hwnd = ffi.C.GetForegroundWindow()
    if fg_hwnd == nil then return false end
    
    -- Create a pointer to hold the resulting Process ID
    local pid_ptr = ffi.new("unsigned long[1]")
    ffi.C.GetWindowThreadProcessId(fg_hwnd, pid_ptr)
    
    local fg_pid = pid_ptr[0]
    local current_pid = ffi.C.GetCurrentProcessId()
    
    -- Returns true ONLY if the active window is our specific PSOBB instance
    return fg_pid == current_pid
end

-- === STATE MANAGEMENT ===
local optionsLoaded, options = pcall(require, "AutoMagFeeder.options")
local optionsFileName = "addons/AutoMagFeeder/options.lua"

if optionsLoaded then
    options.enable = lib_helpers.NotNilOrDefault(options.enable, true)
    options.enable_safety_checks = lib_helpers.NotNilOrDefault(options.enable_safety_checks, true)
    options.lock_inputs = lib_helpers.NotNilOrDefault(options.lock_inputs, true) -- ADD THIS
    options.show_toolbox = lib_helpers.NotNilOrDefault(options.show_toolbox, false)
    options.plan_file_path = lib_helpers.NotNilOrDefault(options.plan_file_path, "")
    
    -- Default position values
    options.anchor = lib_helpers.NotNilOrDefault(options.anchor, 1)
    options.x = lib_helpers.NotNilOrDefault(options.x, 100)
    options.y = lib_helpers.NotNilOrDefault(options.y, 100)
    options.w = lib_helpers.NotNilOrDefault(options.w, 480)
    options.h = lib_helpers.NotNilOrDefault(options.h, 400)
    options.resolutionW = lib_helpers.NotNilOrDefault(options.resolutionW, 0)
    options.resolutionH = lib_helpers.NotNilOrDefault(options.resolutionH, 0)
else
    options = {
        enable = true,
        enable_safety_checks = true,
        lock_inputs = true, -- ADD THIS
        show_toolbox = false,
        plan_file_path = "",
        anchor = 1,
        x = 100,
        y = 100,
        w = 480,
        h = 400,
        resolutionW = 0,
        resolutionH = 0
    }
end

local function SaveOptions(opts)
    local file = io.open(optionsFileName, "w")
    if file ~= nil then
        io.output(file)
        io.write("return {\n")
        io.write(string.format("    enable = %s,\n", tostring(opts.enable)))
        io.write(string.format("    enable_safety_checks = %s,\n", tostring(opts.enable_safety_checks)))
        io.write(string.format("    lock_inputs = %s,\n", tostring(opts.lock_inputs))) -- ADD THIS
        io.write(string.format("    show_toolbox = %s,\n", tostring(opts.show_toolbox)))
        io.write(string.format("    plan_file_path = %q,\n", opts.plan_file_path))
        io.write(string.format("    anchor = %d,\n", opts.anchor))
        io.write(string.format("    x = %d,\n", opts.x))
        io.write(string.format("    y = %d,\n", opts.y))
        io.write(string.format("    w = %d,\n", opts.w))
        io.write(string.format("    h = %d,\n", opts.h))
        io.write(string.format("    resolutionW = %d,\n", opts.resolutionW or 0))
        io.write(string.format("    resolutionH = %d\n", opts.resolutionH or 0))
        io.write("}\n")
        io.close(file)
    end
end

-- === CORE STATE & TABLES ===
local last_log_time = 0

local active_feeder_state = {
    plan_loaded = false,
    plan_data = nil,
    current_step_idx = 1,
    items_remaining_in_step = 0,
    is_running = false,
    last_action_tick = 0,
    status_msg = "Addon Ready. Please assign a feeding plan file path.",
    enemy_danger_tripped = false,
    input_lockout_active = false,
    inventory_shortage = false,
    shortage_msg = "",
    game_lost_focus = false, -- NEW: Tracks OS window focus
    post_feed_cooldown = 0,
    cycle_feeds_count = 0,
    user_keypress_paused = false,
    last_keypress_time = 0
}

local available_plans = {}
local selected_plan_index = 1
local plans_scanned = false

-- Mag selection: the user picks which inventory Mag to feed from a dropdown.
-- Tracked by the Mag's stable item id so the choice survives inventory reorders.
local available_mags = {}            -- list of mag info tables (inventory order)
local mag_labels = { "No Mags found" }  -- display strings for the combo
local selected_mag_combo_idx = 1     -- 1-based dropdown position
local selected_mag_id = nil          -- stable item.id of the chosen Mag
local mags_scanned = false

-- Toolbox window UI state
local compact_mode = false           -- minimized view: status + Start/Pause only
local restore_full_size = false      -- force the full size once after Maximize



local macro_state = {
    is_executing = false,
    queue = {},
    items_fed_this_queue = 0,
    current_held_key = nil,
    key_action_tick = 0
}

-- === DIRECTORY SCANNING STATE ===
local function scan_plan_directory()
    available_plans = {}
    local pfile = io.popen('dir "addons\\AutoMagFeeder\\*.lua" /b 2>nul')
    if pfile then
        for filename in pfile:lines() do
            if filename ~= "init.lua" and filename ~= "configuration.lua" and filename ~= "options.lua" then
                table.insert(available_plans, filename)
            end
        end
        pfile:close()
    end
    
    if #available_plans == 0 then
        table.insert(available_plans, "No plans found")
    end
    
    for i, plan in ipairs(available_plans) do
        if string.find(options.plan_file_path or "", plan) then
            selected_plan_index = i
            break
        end
    end
    plans_scanned = true
    debug_log("Directory scanned. Found " .. #available_plans .. " plan(s).")
end

local function get_safe_character()
    if not lib_characters or type(lib_characters.GetSelf) ~= "function" then return nil end
    local char_addr = lib_characters.GetSelf()
    return (char_addr and char_addr ~= 0) and char_addr or nil
end

-- === NATIVE PROXIMITY CHECKER (live entity-array scan) ===
-- The framework/solylib expose no monster list, so we read the live entity array
-- directly, exactly the way the Monster Reader addon does. An enemy "counts" if
-- it has HP > 0, is not flagged dead, and is within max_safety_distance.
local _EntityCount       = 0x00AAE164  -- u32: number of non-player entities
local _PlayerCount       = 0x00AAE168  -- u32: player slots (monsters start after these)
local _Ent_PosX          = 0x38        -- f32
local _Ent_PosZ          = 0x40        -- f32
local _Ent_HP            = 0x334       -- i16
local _Ent_Flags         = 0x30        -- u32: bit 0x0800 set = dead
local _Ent_ID            = 0x1C        -- u16
local _ephineaMonsterArrayPointer = 0x00B5F800
local _entity_array_base = 0           -- resolved lazily from a fixed instruction

local function check_proximity_threats()
    if not options.enable_safety_checks then return false end

    local self_addr = get_safe_character()
    if not self_addr then return false end

    -- Resolve the entity-array base once (same source Monster Reader uses).
    if _entity_array_base == 0 then
        _entity_array_base = pso.read_u32(0x7B4BA0 + 2)
    end
    if _entity_array_base == 0 then return false end

    local px = pso.read_f32(self_addr + _Ent_PosX)
    local pz = pso.read_f32(self_addr + _Ent_PosZ)
    local player_count = pso.read_u32(_PlayerCount)
    local entity_count = pso.read_u32(_EntityCount)
    local max_dist = options.max_safety_distance or 100.0
    local max_sq = max_dist * max_dist

    local ephineaMonsters = pso.read_u32(_ephineaMonsterArrayPointer)

    for i = 0, entity_count - 1 do
        local addr = pso.read_u32(_entity_array_base + 4 * (i + player_count))
        if addr ~= 0 then
            local flags = pso.read_u32(addr + _Ent_Flags)
            -- Alive enemy: positive HP and the dead flag (0x0800) not set.
            if bit.band(flags, 0x0800) == 0 then
                local hp = 0
                if ephineaMonsters ~= 0 then
                    local id = pso.read_u16(addr + _Ent_ID)
                    hp = pso.read_i32(ephineaMonsters + (id * 32) + 0x04)
                else
                    hp = pso.read_i16(addr + _Ent_HP)
                end

                if hp > 0 then
                    local dx = pso.read_f32(addr + _Ent_PosX) - px
                    local dz = pso.read_f32(addr + _Ent_PosZ) - pz
                    if (dx * dx + dz * dz) <= max_sq then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- === ENVIRONMENT & INVENTORY READERS ===
local function is_in_game_instance()
    -- Must be logged into a character
    local char_addr = get_safe_character()
    if not char_addr then return false end

    -- Floor must not be visual lobby (15) or main menu (0xFFFFFFFF)
    local floor = lib_characters.GetCurrentFloorSelf()
    return floor ~= 15 and floor ~= 0xFFFFFFFF and floor ~= 4294967295
end

local function item_matches_hex(item, hex_str)
    if not item or not item.data or not hex_str then return false end
    -- Parse "0x030A00" into { 0x03, 0x0A, 0x00 }
    local h1 = tonumber(string.sub(hex_str, 3, 4), 16)
    local h2 = tonumber(string.sub(hex_str, 5, 6), 16)
    local h3 = tonumber(string.sub(hex_str, 7, 8), 16)
    return item.data[1] == h1 and item.data[2] == h2 and item.data[3] == h3
end

-- Checks if the player has the specified item in their inventory
local function has_item_in_inventory(hex_str)
    local inv = lib_items.GetInventory(lib_items.Me)
    if not inv or not inv.items then return false end
    for _, item in ipairs(inv.items) do
        if item_matches_hex(item, hex_str) then
            return true
        end
    end
    return false
end

-- Checks if a consumable tool is actually valid to appear in the Mag feeding menu
local function is_feedable_item(item)
    if not item or not item.data or item.data[1] ~= 0x03 then return false end
    
    local subType = item.data[2]
    local index = item.data[3]
    
    -- Subtype 0 (Mates): Monomate (0), Dimate (1), Trimate (2)
    if subType == 0x00 then
        return index == 0 or index == 1 or index == 2
    -- Subtype 1 (Fluids): Monofluid (0), Difluid (1), Trifluid (2)
    elseif subType == 0x01 then
        return index == 0 or index == 1 or index == 2
    -- Subtype 3 (Sol Atomizer), 4 (Moon Atomizer), 5 (Star Atomizer)
    elseif subType == 0x03 or subType == 0x04 or subType == 0x05 then
        return index == 0
    -- Subtype 6 (Antidotes): Antidote (0), Antiparalysis (1)
    elseif subType == 0x06 then
        return index == 0 or index == 1
    end
    
    return false
end

-- Build a parsed info table for one Mag inventory item.
local function mag_info(item, mag_idx)
    return {
        id        = item.id,
        name      = item.name or "Mag",
        level     = item.data[3],
        def       = item.mag.def,
        pow       = item.mag.pow,
        dex       = item.mag.dex,
        mind      = item.mag.mind,
        timer     = item.mag.timer,
        mag_index = mag_idx,       -- 0-based position among mags (menu nav offset)
        slot      = item.index,    -- 1-based inventory slot
        equipped  = item.equipped,
    }
end

-- Return the Mag the user selected (by stable item id). Falls back to the equipped
-- Mag, combo-selected index, or first Mag in the inventory if nothing is selected
-- or the stable ID changed.
local function get_selected_mag()
    local inv = lib_items.GetInventory(lib_items.Me)
    if not inv or not inv.items then return nil end

    local equipped_fallback = nil
    local index_fallback = nil
    local first_mag = nil
    local mag_idx = 0
    for _, item in ipairs(inv.items) do
        if item.data[1] == 0x02 then
            local m = mag_info(item, mag_idx)
            if not first_mag then first_mag = m end
            if selected_mag_id ~= nil and item.id == selected_mag_id then
                return m
            end
            if selected_mag_combo_idx ~= nil and (mag_idx + 1) == selected_mag_combo_idx then
                index_fallback = m
            end
            if item.equipped and equipped_fallback == nil then
                equipped_fallback = m
            end
            mag_idx = mag_idx + 1
        end
    end
    return equipped_fallback or index_fallback or first_mag
end

-- Returns four values sourced from solylib's inventory reader:
--   mag_offset, mag_count   -- selected Mag's 0-based position among mags, and the mag total
--   food_offset, food_count -- target food's 0-based position among feedable items, and that total
-- The counts let the macro pick the shortest cursor path (Up vs Down) in each
-- wrapping menu list. mag_offset/food_offset are nil if not found (no Mag selected,
-- or the food isn't carried), which the callers treat as a shortage. Note an
-- offset can be 0 (first in the list) -- 0 is truthy in Lua, so guard with `nil`.
local function calculate_ui_offsets(target_hex_str)
    -- inv.items is ordered exactly like the in-game item list, and each item
    -- carries .index (1-based slot), .equipped, and parsed .data[].
    local inv = lib_items.GetInventory(lib_items.Me)
    if not inv or not inv.items then return nil, 0, nil, 0 end

    local resolved_mag = get_selected_mag()
    local target_mag_id = resolved_mag and resolved_mag.id or nil

    local mag_offset = nil
    local food_offset = nil
    local mag_seen = 0
    local feedable_seen = 0

    for _, item in ipairs(inv.items) do
        -- Mag (item type 0x02). The F4 Mag menu lists mags in inventory order, so
        -- the cursor distance is the SELECTED Mag's position AMONG MAGS (0-based) --
        -- matching the AHK's per-mag navigation.
        if item.data[1] == 0x02 then
            if mag_offset == nil then
                if target_mag_id ~= nil then
                    if item.id == target_mag_id then mag_offset = mag_seen end
                elseif item.equipped then
                    mag_offset = mag_seen
                end
            end
            mag_seen = mag_seen + 1
        end

        -- The "give item to mag" submenu lists feedable consumables only, in
        -- inventory order. Count how many precede the target to get its offset.
        if is_feedable_item(item) then
            if food_offset == nil and item_matches_hex(item, target_hex_str) then
                food_offset = feedable_seen
            end
            feedable_seen = feedable_seen + 1
        end
    end

    -- Fallback: if we still didn't find the mag offset but we have mags,
    -- fall back to the first mag or the combo index
    if mag_offset == nil and mag_seen > 0 then
        if selected_mag_combo_idx ~= nil and selected_mag_combo_idx <= mag_seen then
            mag_offset = selected_mag_combo_idx - 1
        else
            mag_offset = 0
        end
    end

    -- mag_seen / feedable_seen are now the totals (counts).
    return mag_offset, mag_seen, food_offset, feedable_seen
end


-- Rescan inventory for all Mags and rebuild the dropdown list. Keeps the current
-- selection if it still exists, otherwise defaults to the equipped Mag (or first).
local function scan_mags()
    available_mags = {}
    mag_labels = {}
    local inv = lib_items.GetInventory(lib_items.Me)
    if inv and inv.items then
        local mag_idx = 0
        for _, item in ipairs(inv.items) do
            if item.data[1] == 0x02 then
                local m = mag_info(item, mag_idx)
                table.insert(available_mags, m)
                table.insert(mag_labels, string.format("%s  Lv%d  %.2f/%.2f/%.2f/%.2f%s",
                    m.name, m.level, m.def, m.pow, m.dex, m.mind,
                    m.equipped and "  [Equipped]" or ""))
                mag_idx = mag_idx + 1
            end
        end
    end

    if #available_mags == 0 then
        mag_labels = { "No Mags found" }
        selected_mag_id = nil
        selected_mag_combo_idx = 1
    else
        local found = nil
        for i, m in ipairs(available_mags) do
            if m.id == selected_mag_id then found = i break end
        end
        if not found then
            local def_i = 1
            for i, m in ipairs(available_mags) do if m.equipped then def_i = i break end end
            found = def_i
            selected_mag_id = available_mags[def_i].id
        end
        selected_mag_combo_idx = found
    end
    mags_scanned = true
    debug_log("Mag scan: found " .. #available_mags .. " mag(s).")
end

-- === PLAN PARSING & SEQUENCE TRACKING LOGIC ===
local function calculate_plan_resume_point(mag, plan_data)
    local sequence = plan_data.sequence
    local tolerance = 0.05 -- Allow small float discrepancies (e.g., 0.05 stat points)
    local inactive_tolerance = 0.99 -- Allow side-effect fluctuations on inactive stats (up to 0.99 levels)
    
    -- Enforce strict 0.05 tolerance for stats that start at 0.00 and are never active in the plan.
    local is_active_in_plan = { def = false, pow = false, dex = false, mind = false }
    for _, step in ipairs(sequence) do
        local feed = step.feed_value
        if feed.def > 0 then is_active_in_plan.def = true end
        if feed.pow > 0 then is_active_in_plan.pow = true end
        if feed.dex > 0 then is_active_in_plan.dex = true end
        if feed.mind > 0 then is_active_in_plan.mind = true end
    end
    
    local step1 = sequence[1]
    if step1 then
        local start1 = step1.start_state
        if not is_active_in_plan.def and start1.def == 0 and mag.def > tolerance then return nil, nil end
        if not is_active_in_plan.pow and start1.pow == 0 and mag.pow > tolerance then return nil, nil end
        if not is_active_in_plan.dex and start1.dex == 0 and mag.dex > tolerance then return nil, nil end
        if not is_active_in_plan.mind and start1.mind == 0 and mag.mind > tolerance then return nil, nil end
    end
    
    for i = 1, #sequence do
        local step = sequence[i]
        local feed = step.feed_value
        local start = step.start_state
        
        -- 1. Check inactive stats (where feed_value is 0).
        -- They must remain equal to their starting values for this step.
        local inactive_match = true
        if feed.def == 0 and math.abs(mag.def - start.def) > inactive_tolerance then inactive_match = false end
        if feed.pow == 0 and math.abs(mag.pow - start.pow) > inactive_tolerance then inactive_match = false end
        if feed.dex == 0 and math.abs(mag.dex - start.dex) > inactive_tolerance then inactive_match = false end
        if feed.mind == 0 and math.abs(mag.mind - start.mind) > inactive_tolerance then inactive_match = false end
        
        if step.mag_name and step.mag_name ~= "" then
            if string.lower(mag.name) ~= string.lower(step.mag_name) then
                inactive_match = false
            end
        end
        
        if inactive_match then
            -- 2. Calculate items fed based on active stats (where feed_value > 0).
            local active_feeds = {}
            if feed.def > 0 then
                table.insert(active_feeds, (mag.def - start.def) * 100 / feed.def)
            end
            if feed.pow > 0 then
                table.insert(active_feeds, (mag.pow - start.pow) * 100 / feed.pow)
            end
            if feed.dex > 0 then
                table.insert(active_feeds, (mag.dex - start.dex) * 100 / feed.dex)
            end
            if feed.mind > 0 then
                table.insert(active_feeds, (mag.mind - start.mind) * 100 / feed.mind)
            end
            
            -- If there are active stats, verify they all agree on the progress.
            if #active_feeds > 0 then
                local first_val = active_feeds[1]
                local all_agree = true
                local min_val = first_val
                local max_val = first_val
                
                for j = 2, #active_feeds do
                    local val = active_feeds[j]
                    if val < min_val then min_val = val end
                    if val > max_val then max_val = val end
                end
                
                -- The difference between the highest and lowest calculated feeds
                -- should not exceed a reasonable tolerance (e.g., 2 feeds).
                if (max_val - min_val) > 2.0 then
                    all_agree = false
                end
                
                -- Check if progress is within the bounds of this step [0, step.count]
                local avg_feeds = (min_val + max_val) / 2
                local rounded_feeds = math.floor(avg_feeds + 0.5)
                
                if all_agree and rounded_feeds >= 0 and rounded_feeds <= step.count then
                    local items_remaining = step.count - rounded_feeds
                    if items_remaining > 0 then
                        return i, items_remaining
                    end
                end
            else
                -- Special case: step has count > 0 but all feed values are 0
                return i, step.count
            end
        end
    end
    
    -- If no active step matched, check if the Mag matches the final completed state of the last step.
    if #sequence > 0 then
        local last_step = sequence[#sequence]
        local feed = last_step.feed_value
        local start = last_step.start_state
        local count = last_step.count
        
        local final_def  = start.def  + (feed.def  * count / 100)
        local final_pow  = start.pow  + (feed.pow  * count / 100)
        local final_dex  = start.dex  + (feed.dex  * count / 100)
        local final_mind = start.mind + (feed.mind * count / 100)
        
        if math.abs(mag.def - final_def) <= tolerance and
           math.abs(mag.pow - final_pow) <= tolerance and
           math.abs(mag.dex - final_dex) <= tolerance and
           math.abs(mag.mind - final_mind) <= tolerance then
            return #sequence, 0
        end
    end
    
    return nil, nil
end

local function track_plan_state()
    if not active_feeder_state.plan_data or not active_feeder_state.plan_data.sequence then
        active_feeder_state.inventory_shortage = true
        active_feeder_state.shortage_msg = "No operational plan timeline currently assigned."
        return
    end
    
    local sequence = active_feeder_state.plan_data.sequence
    local idx = active_feeder_state.current_step_idx
    
    if idx > #sequence then
        active_feeder_state.is_running = false
        active_feeder_state.items_remaining_in_step = 0
        active_feeder_state.status_msg = "Finished: Entire Mag feeding plan execution successful!"
        active_feeder_state.inventory_shortage = false
        return
    end

    local current_step = sequence[idx]
    if active_feeder_state.items_remaining_in_step <= 0 then
        active_feeder_state.items_remaining_in_step = tonumber(current_step.count) or 0
    end
    
    local is_mag_cell = current_step.is_mag_cell
    local has_food = false
    local mag_offset = nil
    
    if is_mag_cell then
        has_food = has_item_in_inventory(current_step.item_id)
        local resolved_mag = get_selected_mag()
        if resolved_mag then
            mag_offset = resolved_mag.mag_index
        end
    else
        local food_offset
        mag_offset, _, food_offset = calculate_ui_offsets(current_step.item_id)
        has_food = (food_offset ~= nil)
    end

    if not has_food then
        active_feeder_state.inventory_shortage = true
        active_feeder_state.shortage_msg = string.format("Shortage: Missing [%s] for step %d.", current_step.item, idx)
        if active_feeder_state.is_running then
            active_feeder_state.is_running = false
            active_feeder_state.status_msg = "Suspended: Automatic loop stopped due to inventory shortages."
            debug_log(active_feeder_state.status_msg)
        end
    elseif not mag_offset then
        active_feeder_state.inventory_shortage = true
        active_feeder_state.shortage_msg = "Shortage: Selected Mag not found. Refresh Mags."
    else
        active_feeder_state.inventory_shortage = false
        active_feeder_state.shortage_msg = ""
    end

    if active_feeder_state.is_running and not macro_state.is_executing then
        active_feeder_state.status_msg = string.format("Feeding Running: Processing step %d/%d (%d left)", 
            idx, #sequence, active_feeder_state.items_remaining_in_step)
    end
end

-- === PLAN LOADER ===
local function load_feeder_plan(filepath)
    debug_log("Attempting to load plan at: " .. filepath)
    active_feeder_state.plan_loaded = false
    active_feeder_state.plan_data = nil
    active_feeder_state.is_running = false
    
    -- Capture 'result' as the error message if success is false
    local success, result = pcall(dofile, filepath)

    if not success then
        -- This logs the specific Lua error (e.g., "syntax error: ...")
        active_feeder_state.status_msg = "Error: Failed to load file. " .. tostring(result)
        debug_log(active_feeder_state.status_msg)
        return false
    end

    if type(result) ~= "table" then
        active_feeder_state.status_msg = "Error: File did not return a table."
        debug_log(active_feeder_state.status_msg)
        return false
    end

    if not result.target_mag or not result.sequence then
        active_feeder_state.status_msg = "Format Error: Target fields 'target_mag' or 'sequence' missing."
        debug_log(active_feeder_state.status_msg)
        return false
    end

    -- Translate legacy or incorrect plan item IDs and class IDs to correct PSOBB values dynamically
    for _, step in ipairs(result.sequence) do
        local key = step.item
        if key == "Sol atomizer" then key = "Sol Atomizer"
        elseif key == "Moon atomizer" then key = "Moon Atomizer"
        elseif key == "Star atomizer" then key = "Star Atomizer"
        end
        local correct_id = ITEM_NAME_TO_ID[key]
        if correct_id then
            step.item_id = correct_id
        end
        if step.class_name and lib_characters.Classes[step.class_name] then
            step.class_id = lib_characters.Classes[step.class_name]
        end
    end

    local mag = get_selected_mag()
    if not mag then
        active_feeder_state.status_msg = "Error: No Mag selected/found. Refresh Mags and pick one."
        debug_log(active_feeder_state.status_msg)
        return false
    end

    local resume_idx, resume_count = calculate_plan_resume_point(mag, result)
    
    if not resume_idx then
        active_feeder_state.status_msg = "Error: Equipped Mag stats do not match this plan!"
        debug_log(string.format("SYNC ERROR: Mag stats [%.2f/%.2f/%.2f/%.2f] do not match plan '%s'.", 
            mag.def, mag.pow, mag.dex, mag.mind, result.target_mag))
        return false
    end
    
    if resume_count <= 0 then
        active_feeder_state.status_msg = "Finished: This Mag has already completed this plan."
        debug_log(active_feeder_state.status_msg)
        return false
    end

    local current_step = result.sequence[resume_idx]
    
    -- 1. Get the address
    local char_addr = get_safe_character() 
    if not char_addr then
        active_feeder_state.status_msg = "Error: Player character not found. Are you logged in?"
        debug_log(active_feeder_state.status_msg)
        return false
    end
    
    -- 2. Use the address to read the actual data using lib_characters
    local char_class_id = lib_characters.GetPlayerClass(char_addr)
    local char_sec_id   = lib_characters.GetPlayerSectionID(char_addr)
    
    -- 3. Now use these variables for your comparison
    local char_section_name = SECTION_IDS[char_sec_id] or "Unknown"

    if char_class_id ~= current_step.class_id or char_section_name ~= current_step.section_id then
        active_feeder_state.status_msg = string.format("Character Mismatch: Step %d requires a %s %s.", 
            resume_idx, current_step.section_id, current_step.class_name)
        debug_log(active_feeder_state.status_msg)
        return false
    end



    active_feeder_state.plan_data = result
    active_feeder_state.current_step_idx = resume_idx
    active_feeder_state.items_remaining_in_step = resume_count
    active_feeder_state.plan_loaded = true
    active_feeder_state.cycle_feeds_count = 0
    
    active_feeder_state.status_msg = string.format("Synced! Resuming '%s' at Step %d (%d %s remaining)", 
        result.target_mag, resume_idx, resume_count, current_step.item)
    debug_log("SUCCESS: " .. active_feeder_state.status_msg)
        
    return true
end

-- === NATIVE INTERRUPT SCANNER ===
-- Keys the macro itself drives (plus mouse buttons) must NOT count as a user
-- interrupt, or the feeder would cancel itself.
local INTERRUPT_IGNORE = {
    [0x01] = true, [0x02] = true, [0x04] = true, -- Left, Right, Middle Mouse
    [0x0D] = true, -- ENTER
    [0x26] = true, -- UP
    [0x28] = true, -- DOWN
    [0x1B] = true, -- ESC
    [0x73] = true, -- F4
    [0x7B] = true, -- F12
}

local function get_interrupt_key()
    for vkey = 0x08, 0xFE do
        if not INTERRUPT_IGNORE[vkey] then
            if bit.band(ffi.C.GetAsyncKeyState(vkey), 0x8000) ~= 0 then
                return vkey
            end
        end
    end
    return nil
end
-- === CORE FEED ENGINE EXECUTION TICK ===
local function execute_feeder_tick()
    local char_addr = get_safe_character()
    if not char_addr then return end

    local current_time = pso.get_tick_count()
    
    -- 0. CONTINUOUS INVENTORY & STATE TRACKING
    -- This dynamically updates step items remaining and automatically clears
    -- inventory shortages when the player buys or replenishes their items.
    track_plan_state()

    local mag = get_selected_mag()
    if mag then
        -- Reset cycle count if the timer has expired or is close to expiring (and we are not feeding / cooling down)
        if not macro_state.is_executing and current_time >= active_feeder_state.post_feed_cooldown then
            if mag.timer <= 2.0 then
                active_feeder_state.cycle_feeds_count = 0
            end
        end
    end

    -- Auto-sync progress from memory when not actively feeding or in cooldown.
    -- This handles tracking manual feeds and recovering from desyncs.
    if mag and active_feeder_state.plan_loaded and not macro_state.is_executing and current_time >= active_feeder_state.post_feed_cooldown then
        local resume_idx, resume_count = calculate_plan_resume_point(mag, active_feeder_state.plan_data)
        if resume_idx then
            if active_feeder_state.current_step_idx ~= resume_idx or active_feeder_state.items_remaining_in_step ~= resume_count then
                local diff = 0
                if active_feeder_state.current_step_idx == resume_idx then
                    diff = active_feeder_state.items_remaining_in_step - resume_count
                else
                    local old_step = active_feeder_state.plan_data.sequence[active_feeder_state.current_step_idx]
                    local new_step = active_feeder_state.plan_data.sequence[resume_idx]
                    if old_step and new_step then
                        diff = active_feeder_state.items_remaining_in_step + ((tonumber(new_step.count) or 0) - resume_count)
                    end
                end

                debug_log(string.format("Auto-sync: Syncing progress from memory. Step %d -> %d, Items remaining %d -> %d, Cycle feeds adjust: %d",
                    active_feeder_state.current_step_idx, resume_idx, active_feeder_state.items_remaining_in_step, resume_count, diff))
                
                active_feeder_state.current_step_idx = resume_idx
                active_feeder_state.items_remaining_in_step = resume_count
                active_feeder_state.cycle_feeds_count = math.max(0, math.min(3, active_feeder_state.cycle_feeds_count + diff))
            end
        else
            if active_feeder_state.is_running then
                active_feeder_state.is_running = false
                active_feeder_state.status_msg = "Desync Error: Mag stats do not match the plan. Feeding suspended."
                debug_log(string.format("SYNC ERROR: Mag stats [%.2f/%.2f/%.2f/%.2f] do not match plan '%s'.", 
                    mag.def, mag.pow, mag.dex, mag.mind, active_feeder_state.plan_data.target_mag))
            end
        end
    end

    -- 1. MASTER SAFETY & PAUSE OVERRIDES 
    local abort_execution = false
    if not is_game_window_active() then
        if active_feeder_state.is_running then
            debug_log("Paused: Game window lost focus.")
        end
        active_feeder_state.is_running = false
        active_feeder_state.enemy_danger_tripped = false
        abort_execution = true
    elseif not is_in_game_instance() then
        if active_feeder_state.is_running then
            active_feeder_state.status_msg = "Paused: Character in visual lobby or main menu."
            debug_log("Paused: Feeder stopped because player is in a lobby or menu.")
        end
        active_feeder_state.is_running = false
        active_feeder_state.enemy_danger_tripped = false
        abort_execution = true
    elseif not active_feeder_state.is_running then
        active_feeder_state.enemy_danger_tripped = false
        abort_execution = true
    end

    if abort_execution then
        if macro_state.is_executing then
            if macro_state.current_held_key then
                key_up(macro_state.current_held_key)
                macro_state.current_held_key = nil
            end
            macro_state.queue = {}
            macro_state.is_executing = false
            active_feeder_state.post_feed_cooldown = current_time + 5000
            debug_log("Macro aborted.")
        end
        active_feeder_state.user_keypress_paused = false
        return 
    end

    -- 2. USER KEYPRESS INTERRUPT GATE (Lock inputs)
    if options.lock_inputs then
        local should_check_interrupt = macro_state.is_executing
        if not should_check_interrupt then
            if mag and mag.timer <= 4.0 and current_time >= active_feeder_state.post_feed_cooldown then
                should_check_interrupt = true
            end
        end

        if should_check_interrupt or active_feeder_state.user_keypress_paused then
            local int_key = get_interrupt_key()
            if int_key then
                active_feeder_state.last_keypress_time = current_time
                if not active_feeder_state.user_keypress_paused then
                    active_feeder_state.user_keypress_paused = true
                    active_feeder_state.status_msg = "Keyboard Override: user keypress detected -- feeding paused until clear."
                    debug_log(string.format("User keypress detected -- pausing feed (Key: 0x%02X).", int_key))
                    if macro_state.is_executing then
                        if macro_state.current_held_key then
                            key_up(macro_state.current_held_key)
                            macro_state.current_held_key = nil
                        end
                        macro_state.queue = {}
                        macro_state.is_executing = false
                        active_feeder_state.post_feed_cooldown = current_time + 5000
                        debug_log("Macro aborted.")
                    end
                end
            end
        end

        if active_feeder_state.user_keypress_paused then
            if (current_time - active_feeder_state.last_keypress_time) < 5000 then
                return
            else
                active_feeder_state.user_keypress_paused = false
                active_feeder_state.status_msg = "User input idle -- resuming feed."
                debug_log("User input idle -- resuming feed.")
            end
        end
    end

    -- 3. PROXIMITY SAFETY GATE (Combat override)
    if is_in_game_instance() and check_proximity_threats() then
        if not active_feeder_state.enemy_danger_tripped then
            active_feeder_state.enemy_danger_tripped = true
            active_feeder_state.status_msg = "Combat Override: enemies nearby -- feeding paused until clear."
            debug_log("Proximity threat detected -- pausing feed until the area clears.")
        end
        if macro_state.is_executing then
            if macro_state.current_held_key then
                key_up(macro_state.current_held_key)
                macro_state.current_held_key = nil
            end
            macro_state.queue = {}
            macro_state.is_executing = false
            active_feeder_state.post_feed_cooldown = current_time + 5000
            debug_log("Macro aborted due to combat proximity.")
        end
        return
    elseif active_feeder_state.enemy_danger_tripped then
        active_feeder_state.enemy_danger_tripped = false
        active_feeder_state.status_msg = "Area clear -- resuming feed."
        debug_log("Area clear -- resuming feed.")
    end

    -- 4. MACRO STATE MACHINE
    if macro_state.is_executing then
        -- Phase A: Key Release
        if macro_state.current_held_key then
            if (current_time - macro_state.key_action_tick) >= KEY_PRESS_HOLD_MS then
                key_up(macro_state.current_held_key)
                macro_state.current_held_key = nil
                macro_state.key_action_tick = current_time
            end
            return 
        end
        -- Phase B: Key Press (only once the inter-key delay has elapsed)
        if (current_time - macro_state.key_action_tick) >= KEY_DELAY_MS then
            if #macro_state.queue > 0 then
                local entry = table.remove(macro_state.queue, 1)
                local vk_code
                local is_feed = false
                if type(entry) == "table" then
                    vk_code = entry.vk
                    is_feed = entry.is_feed
                else
                    vk_code = entry
                end

                key_down(vk_code)
                macro_state.current_held_key = vk_code
                macro_state.key_action_tick = current_time

                if is_feed then
                    active_feeder_state.items_remaining_in_step = math.max(0, active_feeder_state.items_remaining_in_step - 1)
                    active_feeder_state.cycle_feeds_count = active_feeder_state.cycle_feeds_count + 1
                    debug_log(string.format("Feed key sent. Items remaining in step: %d, Cycle feeds: %d", 
                        active_feeder_state.items_remaining_in_step, active_feeder_state.cycle_feeds_count))
                end
            else
                -- Whole queue sent: finish this feed batch.
                macro_state.is_executing = false
                if active_feeder_state.items_remaining_in_step <= 0 then
                    active_feeder_state.current_step_idx = active_feeder_state.current_step_idx + 1
                end
                -- 5s cooldown so the server updates the Mag timer before we re-read it.
                active_feeder_state.post_feed_cooldown = current_time + 5000
                active_feeder_state.last_action_tick = current_time + 5000
                debug_log("Feed batch complete. Cooling down 5s to sync Mag timer...")
            end
        end
        -- If the inter-key delay has not elapsed yet, just wait for the next tick.
        return
    end

    -- 3. PLAN DATA GUARD (Prevents the "nil" crash)
    if not active_feeder_state.plan_data or not active_feeder_state.plan_data.sequence then return end

    -- If we are in the 5-second post-feed cooldown, do nothing
    if current_time < active_feeder_state.post_feed_cooldown then
        return 
    end

    -- Now it is safe to check the timer
    if mag and mag.timer > 2.0 then
        if active_feeder_state.cycle_feeds_count >= 3 or active_feeder_state.cycle_feeds_count == 0 then
            if (current_time - last_log_time) > 15000 then
                debug_log(string.format("Digest mode: %.1f sec remaining", mag.timer))
                last_log_time = current_time
            end
            return
        end
    end
    
    -- 4. GENERATE MACRO QUEUE
    local seq = active_feeder_state.plan_data.sequence
    local step = seq[active_feeder_state.current_step_idx]
    if not step then return end
    
    if step.is_mag_cell then
        active_feeder_state.is_running = false
        active_feeder_state.status_msg = string.format("Plan Paused: Please manually use [%s] on your Mag, then click Start.", step.item)
        debug_log(active_feeder_state.status_msg)
        active_feeder_state.current_step_idx = active_feeder_state.current_step_idx + 1
        active_feeder_state.items_remaining_in_step = 0
        active_feeder_state.cycle_feeds_count = 0
        return
    end
    
    local mag_offset, mag_count, food_offset, food_count = calculate_ui_offsets(step.item_id)
    if mag_offset and food_offset then
        local max_feeds_allowed = math.max(0, 3 - active_feeder_state.cycle_feeds_count)
        local feeds = math.min(max_feeds_allowed, active_feeder_state.items_remaining_in_step)
        if feeds <= 0 then return end

        local q = {}
        local function push(k) q[#q + 1] = k end
        local function push_feed(k) q[#q + 1] = { vk = k, is_feed = true } end
        local function push_nav(offset, count)
            for _, k in ipairs(nav_presses(offset, count)) do push(k) end
        end

        -- Feed-menu path (AHK FMg model: each feed is a self-contained
        -- open -> feed -> close cycle, so every iteration ends by clearing all
        -- menus; menu lists wrap top<->bottom):
        --   F12, ESC            -> guarantee all menus closed before we start
        --   then loop x3 (one full cycle per feed):
        --     F4                -> open the Mag menu
        --     nav -> Mag        -> shortest Up/Down to the selected Mag
        --     ENTER             -> select the Mag
        --     ENTER             -> choose "feed"
        --     nav -> item       -> shortest Up/Down to the target consumable
        --     ENTER             -> feed
        --     F4                -> close the menu (clears all menus)
        push(VK_F12); push(VK_ESCAPE)
        for _ = 1, feeds do
            push(VK_F4)
            push_nav(mag_offset, mag_count)
            push(VK_RETURN)               -- select the Mag
            push(VK_RETURN)               -- choose "feed"
            push_nav(food_offset, food_count)
            push_feed(VK_RETURN)          -- feed
            push(VK_F4)                   -- close (clears all menus)
        end

        macro_state.queue = q
        macro_state.is_executing = true
        macro_state.key_action_tick = current_time - KEY_DELAY_MS
        debug_log(string.format("Queue (F4/feed): mag %d/%d, food %d/%d, feeds %d (%d keys)",
            mag_offset, mag_count, food_offset, food_count, feeds, #q))
    else
        -- Can't build a feed: the selected Mag or the step's food isn't available.
        -- Stop the loop (rather than silently retrying / re-logging every frame)
        -- and report exactly why.
        active_feeder_state.is_running = false
        active_feeder_state.inventory_shortage = true
        if not mag_offset then
            active_feeder_state.shortage_msg = "Selected Mag not found. Refresh Mags and re-select."
        else
            active_feeder_state.shortage_msg = string.format("Out of %s for step %d.",
                step.item, active_feeder_state.current_step_idx)
        end
        active_feeder_state.status_msg = "Suspended: " .. active_feeder_state.shortage_msg
        debug_log(active_feeder_state.status_msg)
    end
end

-- === GUI / MENU PRESENTATION ===
local function present()
    -- Run the feed engine every frame (independent of window visibility).
    execute_feeder_tick()

    if not options.show_toolbox then return end

    local resizeFlag = compact_mode and "AlwaysAutoResize" or nil
    lib_helpers.PrepareWindowPositionAndSize("AutoMag Feeder Control Toolbox", options, "x", "y", "w", "h", "anchor", resizeFlag)

    -- Window sizing & open-state. Begin's 2nd return is the [X] open flag.
    --   Compact: auto-fit the small status bar (AlwaysAutoResize).
    --   Full:    "FirstUseEver" so a manual resize sticks.
    local draw, keep_open
    if compact_mode then
        draw, keep_open = ImGui.Begin("AutoMag Feeder Control Toolbox", true, { "AlwaysAutoResize" })
    else
        if restore_full_size then
            ImGui.SetNextWindowSize(options.w, options.h, "Always")  -- restore once after Maximize
            restore_full_size = false
        end
        draw, keep_open = ImGui.Begin("AutoMag Feeder Control Toolbox", true)
    end

    if draw then
        lib_helpers.TrackWindowPosition("AutoMag Feeder Control Toolbox", options, "x", "y", "w", "h", "anchor", function() SaveOptions(options) end, resizeFlag)

        -- === Always visible: status + Start/Pause + Minimize/Maximize ===
        ImGui.TextColored(0.25, 0.82, 0.88, 1.0, "Status:")
        if active_feeder_state.is_running then
            ImGui.SameLine(); ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "[RUNNING]")
        end

        if active_feeder_state.inventory_shortage then
            ImGui.TextColored(1.0, 0.5, 0.0, 1.0, active_feeder_state.shortage_msg)
        else
            ImGui.TextColored(0.5, 0.5, 1.0, 1.0, active_feeder_state.status_msg)
        end
        if active_feeder_state.enemy_danger_tripped then
            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, "--> Combat: enemies nearby -- paused until clear.")
        end

        if not active_feeder_state.is_running then
            local disabled = not active_feeder_state.plan_loaded
            if disabled then ImGui.PushStyleVar("Alpha", 0.5) end
            if ImGui.Button("Start") and not disabled then
                active_feeder_state.is_running = true
                active_feeder_state.last_action_tick = pso.get_tick_count()
                debug_log("Automation Started.")
            end
            if disabled then ImGui.PopStyleVar() end
        else
            if ImGui.Button("Pause") then
                active_feeder_state.is_running = false
                active_feeder_state.status_msg = "Paused: halted by operator."
                debug_log("Automation Paused.")
            end
        end

        ImGui.SameLine()
        if compact_mode then
            if ImGui.Button("Maximize") then
                compact_mode = false
                restore_full_size = true
            end
        else
            if ImGui.Button("Minimize") then
                compact_mode = true
            end
        end

        -- === Full view only: plan/mag selection, load, reset, settings, log ===
        if not compact_mode then
            ImGui.Separator()

            if not plans_scanned then scan_plan_directory() end
            local btn_w_folder = ImGui.CalcTextSize("Refresh Folder") + 20
            local padding = 15
            local spacing = 8
            local combo_start_x = 100
            local window_w = ImGui.GetWindowWidth()

            ImGui.Text("Select Plan")
            ImGui.SameLine()
            ImGui.SetCursorPosX(combo_start_x)
            local item_w_folder = window_w - btn_w_folder - padding - combo_start_x - spacing
            if item_w_folder < 50 then item_w_folder = 50 end
            ImGui.PushItemWidth(item_w_folder)
            local plan_changed, plan_new = ImGui.Combo("##Select Plan", selected_plan_index, available_plans, #available_plans)
            if plan_changed and available_plans[plan_new] ~= "No plans found" then
                selected_plan_index = plan_new
                options.plan_file_path = "addons/AutoMagFeeder/" .. available_plans[plan_new]
                SaveOptions(options)
                debug_log("Plan selected: " .. available_plans[plan_new])
            end
            ImGui.PopItemWidth()
            ImGui.SameLine(window_w - btn_w_folder - padding)
            if ImGui.Button("Refresh Folder") then scan_plan_directory() end

            if not mags_scanned then scan_mags() end
            local btn_w_mags = ImGui.CalcTextSize("Refresh Mags") + 20
            ImGui.Text("Select Mag")
            ImGui.SameLine()
            ImGui.SetCursorPosX(combo_start_x)
            local item_w_mags = window_w - btn_w_mags - padding - combo_start_x - spacing
            if item_w_mags < 50 then item_w_mags = 50 end
            ImGui.PushItemWidth(item_w_mags)
            local mag_changed, mag_new = ImGui.Combo("##Select Mag", selected_mag_combo_idx, mag_labels, #mag_labels)
            if mag_changed and available_mags[mag_new] then
                selected_mag_combo_idx = mag_new
                selected_mag_id = available_mags[mag_new].id
                debug_log("Selected Mag: " .. mag_labels[mag_new])
            end
            ImGui.PopItemWidth()
            ImGui.SameLine(window_w - btn_w_mags - padding)
            if ImGui.Button("Refresh Mags") then scan_mags() end

            if ImGui.Button("Load Selected Plan") then
                if options.plan_file_path == nil or options.plan_file_path == "" then
                    active_feeder_state.status_msg = "Choose a plan from the dropdown, or add a .lua plan to addons/AutoMagFeeder"
                    debug_log(active_feeder_state.status_msg)
                else
                    load_feeder_plan(options.plan_file_path)
                end
            end
            ImGui.SameLine()
            if ImGui.Button("Reset Progress") then
                active_feeder_state.is_running = false
                active_feeder_state.current_step_idx = 1
                active_feeder_state.items_remaining_in_step = 0
                active_feeder_state.cycle_feeds_count = 0
                if active_feeder_state.plan_loaded then
                    track_plan_state()
                    active_feeder_state.status_msg = "Timeline reset to step 1."
                    debug_log("Plan timeline reset to Step 1.")
                else
                    active_feeder_state.status_msg = "Registers cleared."
                end
            end

            ImGui.Separator()
            ImGui.TextColored(0.25, 0.82, 0.88, 1.0, "Diagnostics Log:")
            ImGui.BeginChild("DebugLogRegion", 0, 100, true)
            for _, log in ipairs(debug_logs) do
                ImGui.TextUnformatted(log)
            end
            ImGui.EndChild()
        end
    end
    ImGui.End()

    -- [X] clicked -> keep_open is false. Hide the toolbox; reopen it from the
    -- "AutoMag Feeder" main-menu button.
    if keep_open == false then
        options.show_toolbox = false
        SaveOptions(options)
        debug_log("Toolbox closed. Reopen via the AutoMag Feeder menu button.")
    end
end

-- === SYSTEM INITIALIZATION HOOKS ===
local function init()
    -- The feed engine is driven once per frame from present() (the framework's
    -- per-frame addon callback). This framework has no pso.on_tick.
    debug_log("AutoMag Feeder Engine Initialized.")
    
    -- 1. Main-menu button toggles the toolbox window (so the [X] can close it and
    --    this can reopen it). Settings live on a button inside the toolbox.
    local function mainMenuButtonHandler()
        options.show_toolbox = not options.show_toolbox
        SaveOptions(options)
        debug_log("Toolbox " .. (options.show_toolbox and "shown" or "hidden") .. " via menu button.")
    end
    
    -- 2. Register the button into the core_mainmenu UI
    core_mainmenu.add_button("AutoMag Feeder", mainMenuButtonHandler)

    -- 3. Return the metadata and the 'present' loop to the PSOBB Addon framework
    return {
        name = "AutoMagFeeder",
        version = "1.0.0",
        author = "hooty7734",
        description = "Automates Mag feeding sequences via exported plans.",
        present = present,
    }
end

return 
{
    __addon = 
    {
        init = init
    }
}
