singleton_name = "w"

-- =============================================================================
-- Operation: Detonate - world setup + card definitions.
--
-- Theme: a covert ops team pulls equipment cards while trying to dodge the
-- TIME BOMBS hidden in the deck. Card art is a placeholder flat PNG per card
-- (general/images/<id>.png) - repaint them any time, the layout stays.
--
-- Every card is defined here with load_cards_from_data using the same "cards"
-- JSON structure the online image editor exports, INCLUDING localization:
-- titles/descriptions carry loc_keys with English + Turkish strings, so the
-- printable export of this set can be produced in every language at once.
-- =============================================================================

-- REQUIRED for user.lua's cursor sync: the engine only gathers "stick_2"
-- (world mouse position) into _process()'s inputs table for inputs that have
-- a registered display name (see input_manager.gd::gather_local_inputs -
-- "if not input_name in display_names: continue"). Without this call every
-- peer's stick_2 is nil forever and no one's cursor ever shows up (same
-- requirement Hook Up's world.lua has for its own cursor).
set_input_display_name("stick_2", "Mouse")

set_background_color(Color(0.07, 0.08, 0.11, 1))
set_camera_position(Vector2(0, 0))
-- Start fully zoomed OUT so the whole table is visible; players zoom in from
-- here (Zoom In). Keep this in sync with od_manager's cl_zoom init / zoom floor.
set_camera_zoom(Vector2(0.6, 0.6))

-- Persistent on-screen controls (Sit at table / Stand up / Zoom In / Zoom Out).
change_view("table")

set_image({
    name = "od_table",
    image_path = "table",
    position = Vector2(0, 0),
    scale = Vector2(780, 780),
    modulate = Color(0.55, 0.6, 0.7, 1), -- cold "briefing room" tint
    z_index = -10,
})

-- -----------------------------------------------------------------------------
-- Card catalogue: id -> {title, desc (en/tr), art, icon, bg, type, extra kw}
-- -----------------------------------------------------------------------------
local ICONS = {
    bomb = "bomb_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    disarm = "construction_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    attack = "swords_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    skip = "directions_run_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    favor = "handshake_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    shuffle = "shuffle_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    future = "radar_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    nope = "wifi_off_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    weapon = "target_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
}

local CATALOG = {
    { id = "time_bomb", type = "bomb", icon = ICONS.bomb, bg = "(0.32, 0.06, 0.06, 1)",
      en = { "Time Bomb", "Draw this without a Disarm Kit and you are out of the mission." },
      tr = { "Saatli Bomba", "Etkisiz Hale Getirme Kiti olmadan cekersen gorevden elenirsin." } },
    { id = "disarm_kit", type = "disarm", icon = ICONS.disarm, bg = "(0.05, 0.35, 0.32, 1)",
      en = { "Disarm Kit", "Defuses a Time Bomb - then hide the bomb anywhere in the deck." },
      tr = { "Kit: Etkisizlestirme", "Saatli Bombayi cozer - bombayi destede istedigin yere gizle." } },
    { id = "ambush", type = "attack", icon = ICONS.attack, bg = "(0.45, 0.16, 0.05, 1)",
      en = { "Ambush", "End your turn instantly; the next agent must take TWO turns." },
      tr = { "Pusu", "Turun aninda biter; siradaki ajan IKI tur oynamak zorunda kalir." } },
    { id = "retreat", type = "skip", icon = ICONS.skip, bg = "(0.12, 0.25, 0.42, 1)",
      en = { "Retreat", "End your turn without drawing a card." },
      tr = { "Geri Cekil", "Kart cekmeden turunu bitirirsin." } },
    { id = "supply_request", type = "favor", icon = ICONS.favor, bg = "(0.42, 0.32, 0.14, 1)",
      en = { "Supply Request", "Pick an agent: they must hand you a card of their choice." },
      tr = { "Ikmal Talebi", "Bir ajan sec: sana elinden sectigi bir karti vermek zorundadir." } },
    { id = "mission_shuffle", type = "shuffle", icon = ICONS.shuffle, bg = "(0.28, 0.16, 0.4, 1)",
      en = { "Mission Shuffle", "Shuffle the whole deck." },
      tr = { "Gorev Karistirmasi", "Desteyi tamamen karistirir." } },
    { id = "recon_drone", type = "future", icon = ICONS.future, bg = "(0.5, 0.42, 0.06, 1)",
      en = { "Recon Drone", "Secretly look at the top 3 cards of the deck." },
      tr = { "Kesif Dronu", "Destenin en ustundeki 3 karti gizlice gorursun." } },
    { id = "signal_jammer", type = "nope", icon = ICONS.nope, bg = "(0.2, 0.23, 0.3, 1)",
      en = { "Signal Jammer", "Cancel another agent's action card. Jammers can jam jammers." },
      tr = { "Sinyal Kesici", "Baska bir ajanin aksiyon kartini iptal eder. Kesici kesiciyi keser." } },
    { id = "pistol_9mm", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.2, 0.22, 1)",
      en = { "9mm Pistol", "No power alone. Play 2 identical: steal a random card. 3: name a card." },
      tr = { "9mm Tabanca", "Tek basina gucu yok. Ayni silahtan 2: rastgele kart cal. 3: kart iste." } },
    { id = "heavy_revolver", type = "weapon", icon = ICONS.weapon, bg = "(0.24, 0.19, 0.15, 1)",
      en = { "Heavy Revolver", "No power alone. Play 2 identical: steal a random card. 3: name a card." },
      tr = { "Agir Toplu Tabanca", "Tek basina gucu yok. Ayni silahtan 2: rastgele kart cal. 3: kart iste." } },
    { id = "machine_pistol", type = "weapon", icon = ICONS.weapon, bg = "(0.25, 0.25, 0.28, 1)",
      en = { "Machine Pistol", "No power alone. Play 2 identical: steal a random card. 3: name a card." },
      tr = { "Makineli Tabanca", "Tek basina gucu yok. Ayni silahtan 2: rastgele kart cal. 3: kart iste." } },
    { id = "compact_smg", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.23, 0.3, 1)",
      en = { "Compact SMG", "No power alone. Play 2 identical: steal a random card. 3: name a card." },
      tr = { "Kompakt SMG", "Tek basina gucu yok. Ayni silahtan 2: rastgele kart cal. 3: kart iste." } },
    { id = "tactical_handgun", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.26, 0.2, 1)",
      en = { "Tactical Handgun", "No power alone. Play 2 identical: steal a random card. 3: name a card." },
      tr = { "Taktik Tabanca", "Tek basina gucu yok. Ayni silahtan 2: rastgele kart cal. 3: kart iste." } },
}

local cards = {}
local localization = {}
for _, entry in ipairs(CATALOG) do
    localization["od_" .. entry.id .. "_title"] = { en = entry.en[1], tr = entry.tr[1] }
    localization["od_" .. entry.id .. "_desc"] = { en = entry.en[2], tr = entry.tr[2] }
    table.insert(cards, {
        id = entry.id,
        name = entry.en[1],
        keywords = { type = entry.type },
        bg = { type = "color", color = entry.bg },
        corner = {
            text = "", icon = entry.icon, spots = { "tl", "br" }, flip_opposite = true,
            size = 0.11, color = "(1, 1, 1, 0.9)", outline_size = 0,
            outline_color = "(0, 0, 0, 1)",
        },
        layout = { type = "vbox", children = {
            { type = "text", weight = 0.17, pad = 0.015, text = entry.en[1],
              loc_key = "od_" .. entry.id .. "_title", keyword = "title",
              font_size = 0, align = "center", valign = "center",
              color = "(1, 1, 1, 1)", outline_size = 0.14, outline_color = "(0, 0, 0, 1)" },
            { type = "image", weight = 0.5, pad = 0.02, fit = "contain",
              source = "file:" .. entry.id .. ".png", keyword = "art" },
            { type = "text", weight = 0.33, pad = 0.03, text = entry.en[2],
              loc_key = "od_" .. entry.id .. "_desc", keyword = "description",
              font_size = 0, align = "center", valign = "begin",
              color = "(0.95, 0.95, 0.95, 1)", outline_size = 0.08,
              outline_color = "(0, 0, 0, 1)", bg_color = "(0, 0, 0, 0.4)" },
        } },
    })
end

load_cards_from_data({
    kind = "cards",
    set_id = "od",
    name = "Operation Detonate",
    card_w = 750,
    card_h = 1050,
    corner_radius = 0.07,
    safe_margin = 0.05,
    bg = { type = "color", color = "(0.72, 0.11, 0.11, 1)" },
    back = { type = "color", color = "(0.1, 0.12, 0.16, 1)" },
    -- Subtle steel rim around every card so they read against the dark table.
    outline = { enabled = true, color = "(0.85, 0.88, 0.95, 0.85)", width = 0.018 },
    languages = { "en", "tr" },
    localization = localization,
    cards = cards,
}, "od")

card_set_listener("-od_manager")
card_set_hand_ui({ height = 165, separation = -38 })
