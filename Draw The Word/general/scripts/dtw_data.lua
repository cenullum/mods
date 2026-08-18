singleton_name = "dtw_data"

-- =============================================================================
-- Draw The Word - word pool and text helpers (pure logic, runs on every peer).
-- The manager calls these on the HOST to pick words and validate guesses; some
-- text helpers (mask building) are also handy on clients.
--
-- LANGUAGE
-- The pool holds KEYWORDS, not words: "{w_apple}" is "apple" in English and
-- "elma" in Turkish (see general/language/*.json). That buys three things:
--   * every player sees the word in their own language,
--   * a guess is accepted in ANY installed language, so "fox" and "tilki" both
--     win the same round,
--   * the host never has to know what language anybody is playing in.
-- Everything below therefore works on GLYPHS (UTF-8 characters), not bytes:
-- "köpek" is 5 letters even though it is 6 bytes, and Lua's string.lower and the
-- "%a" pattern only understand ASCII.
-- =============================================================================

local word_pool = {
    "{w_apple}", "{w_banana}", "{w_house}", "{w_car}", "{w_tree}", "{w_dog}",
    "{w_cat}", "{w_fish}", "{w_sun}", "{w_moon}", "{w_star}", "{w_cloud}",
    "{w_rain}", "{w_snowman}", "{w_flower}", "{w_boat}", "{w_train}",
    "{w_airplane}", "{w_rocket}", "{w_robot}", "{w_ghost}", "{w_pizza}",
    "{w_burger}", "{w_ice_cream}", "{w_cake}", "{w_donut}", "{w_guitar}",
    "{w_piano}", "{w_drum}", "{w_book}", "{w_pencil}", "{w_clock}",
    "{w_umbrella}", "{w_balloon}", "{w_kite}", "{w_ladder}", "{w_bridge}",
    "{w_castle}", "{w_mountain}", "{w_island}", "{w_volcano}", "{w_rainbow}",
    "{w_lighthouse}", "{w_windmill}", "{w_camera}", "{w_phone}", "{w_computer}",
    "{w_television}", "{w_lamp}", "{w_chair}", "{w_table}", "{w_door}",
    "{w_key}", "{w_crown}", "{w_sword}", "{w_shield}", "{w_anchor}",
    "{w_compass}", "{w_map}", "{w_tent}", "{w_campfire}", "{w_butterfly}",
    "{w_spider}", "{w_snail}", "{w_octopus}", "{w_whale}", "{w_shark}",
    "{w_penguin}", "{w_elephant}", "{w_giraffe}", "{w_lion}", "{w_monkey}",
    "{w_rabbit}", "{w_turtle}", "{w_dragon}", "{w_unicorn}", "{w_snake}",
    "{w_bee}", "{w_ladybug}", "{w_carrot}", "{w_mushroom}", "{w_cactus}",
    "{w_palm_tree}", "{w_football}", "{w_basketball}", "{w_guitar_pick}",
    "{w_glasses}", "{w_hat}", "{w_shoe}", "{w_sock}", "{w_gloves}",
    "{w_scarf}", "{w_ring}", "{w_necklace}", "{w_watch}", "{w_bicycle}",
    "{w_scooter}", "{w_helicopter}", "{w_submarine}", "{w_tractor}", "{w_bus}",
    "{w_traffic_light}", "{w_stop_sign}", "{w_mailbox}", "{w_fence}",
    "{w_well}", "{w_barn}", "{w_snowflake}", "{w_lightning}", "{w_tornado}",
    "{w_waterfall}", "{w_river}", "{w_beach}", "{w_desert}", "{w_forest}",
    "{w_garden}", "{w_swing}", "{w_slide}", "{w_seesaw}", "{w_trampoline}",
    "{w_telescope}", "{w_magnet}", "{w_battery}", "{w_light_bulb}",
    "{w_scissors}", "{w_hammer}", "{w_screwdriver}", "{w_wrench}",
    "{w_paintbrush}", "{w_easel}", "{w_candle}", "{w_fireworks}",
    "{w_gift_box}", "{w_teddy_bear}", "{w_dice}", "{w_playing_card}",
    "{w_chess}", "{w_puzzle}",
}

-- Per-game working pool: words are removed as they are offered so no two drawers
-- get the same choices in one game. Starts empty; dtw_reset_pool() fills it.
-- dtw_get_two_words auto-fills on first call or when nearly exhausted.
local remaining_pool = {}

-- -----------------------------------------------------------------------------
-- UTF-8 helpers
-- Written by hand rather than with Lua 5.4's utf8 library so the mod keeps
-- working whatever the host binds into the sandbox.
-- -----------------------------------------------------------------------------

-- Split a string into an array of characters (not bytes).
local function glyphs(s)
    local out = {}
    local i = 1
    local n = #s
    while i <= n do
        local b = string.byte(s, i)
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        out[#out + 1] = string.sub(s, i, i + len - 1)
        i = i + len
    end
    return out
end

-- Diacritics folded to plain ASCII so "köpek" and "kopek" both count as correct.
-- Turkish first (that is the language we ship), then the usual Latin extras.
local FOLD = {
    ["ç"] = "c", ["Ç"] = "c", ["ğ"] = "g", ["Ğ"] = "g", ["ı"] = "i", ["İ"] = "i",
    ["ö"] = "o", ["Ö"] = "o", ["ş"] = "s", ["Ş"] = "s", ["ü"] = "u", ["Ü"] = "u",
    ["â"] = "a", ["Â"] = "a", ["î"] = "i", ["Î"] = "i", ["û"] = "u", ["Û"] = "u",
    ["á"] = "a", ["à"] = "a", ["ä"] = "a", ["å"] = "a", ["ã"] = "a", ["æ"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["í"] = "i", ["ì"] = "i", ["ï"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["õ"] = "o", ["ø"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["ñ"] = "n", ["ß"] = "s", ["ý"] = "y",
}

-- Uppercase for the revealed hint letters. ASCII plus the Turkish pairs, because
-- string.upper() would mangle multi-byte characters. Anything unknown is shown
-- as it is, which is always safe.
local UPPER = {
    ["ç"] = "Ç", ["ğ"] = "Ğ", ["ı"] = "I", ["i"] = "İ", ["ö"] = "Ö",
    ["ş"] = "Ş", ["ü"] = "Ü",
}

local function upper_glyph(ch)
    if UPPER[ch] then return UPPER[ch] end
    if #ch == 1 then return string.upper(ch) end
    return ch
end

-- Fold a string down to a comparable form: diacritics removed, lowercase, and
-- everything that is not a letter dropped, so "Ice Cream!", "ice cream" and
-- "icecream" compare equal. Characters from non-Latin scripts are kept as they
-- are rather than thrown away, so this does not silently break for a language
-- added later.
function dtw_normalize(s)
    if type(s) ~= "string" then return "" end
    local out = {}
    for _, ch in ipairs(glyphs(s)) do
        local folded = FOLD[ch] or ch
        if #folded == 1 then
            local b = string.byte(folded)
            if b >= 65 and b <= 90 then
                folded = string.char(b + 32)
                b = b + 32
            end
            if b >= 97 and b <= 122 then out[#out + 1] = folded end
        else
            out[#out + 1] = folded
        end
    end
    return table.concat(out)
end

-- Copy the full word list into remaining_pool (called at the start of each game).
function dtw_reset_pool()
    remaining_pool = {}
    for _, w in ipairs(word_pool) do
        table.insert(remaining_pool, w)
    end
end

-- Return two distinct random word KEYWORDS and remove them from the pool so they
-- will not be offered again this game. Refills automatically if the pool runs low.
function dtw_get_two_words()
    if #remaining_pool < 2 then
        dtw_reset_pool()
    end
    local idx_a = math.random(1, #remaining_pool)
    local a = remaining_pool[idx_a]
    table.remove(remaining_pool, idx_a)

    local idx_b = math.random(1, #remaining_pool)
    local b = remaining_pool[idx_b]
    table.remove(remaining_pool, idx_b)

    return { a, b }
end

-- Every accepted spelling of a word keyword: its text in each installed language,
-- normalized. This is what lets a Turkish player type "tilki" and an English one
-- type "fox" in the very same round.
local function accepted_forms(word_key)
    local forms = {}
    for _, text in pairs(translate_all(word_key)) do
        local norm = dtw_normalize(text)
        if norm ~= "" then forms[norm] = true end
    end
    return forms
end

-- HOST: is this guess correct, in any language?
function dtw_matches(guess, word_key)
    local g = dtw_normalize(guess)
    if g == "" then return false end
    return accepted_forms(word_key)[g] == true
end

-- Classic Levenshtein edit distance between two strings.
function dtw_levenshtein(a, b)
    local la, lb = #a, #b
    if la == 0 then return lb end
    if lb == 0 then return la end

    local prev = {}
    for j = 0, lb do prev[j] = j end

    for i = 1, la do
        local cur = { [0] = i }
        local ca = string.byte(a, i)
        for j = 1, lb do
            local cost = 1
            if ca == string.byte(b, j) then cost = 0 end
            local del = prev[j] + 1
            local ins = cur[j - 1] + 1
            local sub = prev[j - 1] + cost
            local m = del
            if ins < m then m = ins end
            if sub < m then m = sub end
            cur[j] = m
        end
        prev = cur
    end
    return prev[lb]
end

-- A guess is "close" (but not exact) when it is within a small edit distance of
-- the answer. Longer answers tolerate a slightly larger distance. Checked against
-- every language, same as dtw_matches.
function dtw_is_close(guess, word_key)
    local g = dtw_normalize(guess)
    if g == "" then return false end
    for answer in pairs(accepted_forms(word_key)) do
        if g ~= answer then
            local threshold = 1
            if #answer >= 6 then threshold = 2 end
            if dtw_levenshtein(g, answer) <= threshold then return true end
        end
    end
    return false
end

-- Count the letters (ignoring spaces) in a word, in glyphs rather than bytes.
function dtw_letter_count(word)
    local count = 0
    for _, ch in ipairs(glyphs(word)) do
        if ch ~= " " then count = count + 1 end
    end
    return count
end

-- Which glyph positions to uncover, chosen the same way on every peer.
-- The host only broadcasts HOW MANY letters are revealed plus a per-round seed;
-- each peer picks the positions itself, because the translated word it is looking
-- at may be a completely different length from the host's.
function dtw_pick_reveals(word, count, seed)
    local eligible = {}
    for i, ch in ipairs(glyphs(word)) do
        if ch ~= " " then eligible[#eligible + 1] = i end
    end

    -- Deterministic Fisher-Yates with a Lehmer generator: same seed in, same
    -- order out, without disturbing the shared math.random state.
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    for i = #eligible, 2, -1 do
        s = (s * 16807) % 2147483647
        local j = (s % i) + 1
        eligible[i], eligible[j] = eligible[j], eligible[i]
    end

    local wanted = math.floor(count)
    if wanted > #eligible then wanted = #eligible end
    local out = {}
    for i = 1, wanted do
        out[eligible[i]] = true
    end
    return out
end

-- Build the masked hint shown to guessers. `revealed` is a set of 1-based glyph
-- indices that should be shown as their real letter; everything else becomes "_".
-- Spaces are rendered as a wider gap so word boundaries are visible.
-- Example: "ice cream" with nothing revealed -> "_ _ _   _ _ _ _ _"
function dtw_build_mask(word, revealed)
    revealed = revealed or {}
    local parts = {}
    for i, ch in ipairs(glyphs(word)) do
        if ch == " " then
            table.insert(parts, " ")
        elseif revealed[i] then
            table.insert(parts, upper_glyph(ch))
        else
            table.insert(parts, "_")
        end
    end
    return table.concat(parts, " ")
end

-- What every client calls to draw the hint: the keyword plus the host's reveal
-- count and seed, resolved into THIS peer's language.
function dtw_local_mask(word_key, revealed_count, seed)
    local word = translate(word_key)
    local revealed = {}
    if math.floor(revealed_count) > 0 then
        revealed = dtw_pick_reveals(word, revealed_count, seed)
    end
    return dtw_build_mask(word, revealed)
end
