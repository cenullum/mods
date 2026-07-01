singleton_name = "dtw_data"

-- =============================================================================
-- Draw The Word - word pool and text helpers (pure logic, runs on every peer).
-- The manager calls these on the HOST to pick words and validate guesses; some
-- text helpers (mask building) are also handy on clients.
-- =============================================================================

-- Pool of common, easy-to-draw nouns. Multi-word answers are allowed: spaces are
-- shown as gaps in the hint and ignored when comparing guesses.
local word_pool = {
    "apple", "banana", "house", "car", "tree", "dog", "cat", "fish", "sun",
    "moon", "star", "cloud", "rain", "snowman", "flower", "boat", "train",
    "airplane", "rocket", "robot", "ghost", "pizza", "burger", "ice cream",
    "cake", "donut", "guitar", "piano", "drum", "book", "pencil", "clock",
    "umbrella", "balloon", "kite", "ladder", "bridge", "castle", "mountain",
    "island", "volcano", "rainbow", "lighthouse", "windmill", "camera",
    "phone", "computer", "television", "lamp", "chair", "table", "door",
    "key", "crown", "sword", "shield", "anchor", "compass", "map", "tent",
    "campfire", "butterfly", "spider", "snail", "octopus", "whale", "shark",
    "penguin", "elephant", "giraffe", "lion", "monkey", "rabbit", "turtle",
    "dragon", "unicorn", "snake", "bee", "ladybug", "carrot", "mushroom",
    "cactus", "palm tree", "football", "basketball", "guitar pick", "glasses",
    "hat", "shoe", "sock", "gloves", "scarf", "ring", "necklace", "watch",
    "bicycle", "scooter", "helicopter", "submarine", "tractor", "bus",
    "traffic light", "stop sign", "mailbox", "fence", "well", "barn",
    "snowflake", "lightning", "tornado", "waterfall", "river", "beach",
    "desert", "forest", "garden", "swing", "slide", "seesaw", "trampoline",
    "telescope", "magnet", "battery", "light bulb", "scissors", "hammer",
    "screwdriver", "wrench", "paintbrush", "easel", "candle", "fireworks",
    "gift box", "teddy bear", "dice", "playing card", "chess", "puzzle",
}

-- Per-game working pool: words are removed as they are offered so no two drawers
-- get the same choices in one game. Starts empty; dtw_reset_pool() fills it.
-- dtw_get_two_words auto-fills on first call or when nearly exhausted.
local remaining_pool = {}

-- Copy the full word list into remaining_pool (called at the start of each game).
function dtw_reset_pool()
    remaining_pool = {}
    for _, w in ipairs(word_pool) do
        table.insert(remaining_pool, w)
    end
end

-- Return two distinct random words and remove them from the pool so they will
-- not be offered again this game. Refills automatically if the pool runs low.
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

-- Lowercase a string and strip everything that is not a letter, so "Ice Cream!",
-- "ice cream" and "icecream" all compare equal.
function dtw_normalize(s)
    if type(s) ~= "string" then return "" end
    s = string.lower(s)
    s = string.gsub(s, "[^%a]", "")
    return s
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
-- the answer. Longer answers tolerate a slightly larger distance.
function dtw_is_close(guess_norm, answer_norm)
    if guess_norm == "" or answer_norm == "" then return false end
    if guess_norm == answer_norm then return false end

    local d = dtw_levenshtein(guess_norm, answer_norm)
    local threshold = 1
    if #answer_norm >= 6 then threshold = 2 end
    return d <= threshold
end

-- Count the letters (ignoring spaces/punctuation) in a word.
function dtw_letter_count(word)
    local count = 0
    for i = 1, #word do
        if string.match(string.sub(word, i, i), "%a") then
            count = count + 1
        end
    end
    return count
end

-- Build the masked hint shown to guessers. `revealed` is a set of 1-based glyph
-- indices that should be shown as their real letter; everything else becomes "_".
-- Spaces are rendered as a wider gap so word boundaries are visible.
-- Example: "ice cream" with nothing revealed -> "_ _ _   _ _ _ _ _"
function dtw_build_mask(word, revealed)
    revealed = revealed or {}
    local parts = {}
    for i = 1, #word do
        local ch = string.sub(word, i, i)
        if ch == " " then
            table.insert(parts, " ")
        elseif revealed[i] then
            table.insert(parts, string.upper(ch))
        else
            table.insert(parts, "_")
        end
    end
    return table.concat(parts, " ")
end
