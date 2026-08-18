singleton_name = "w"

-- =============================================================================
-- MineBlockLand - one-time world setup (runs once on every peer at map load).
-- Day/night visuals, the clock and everything stateful live in -gm; this file
-- only wires the controller, the HUD view and the input hints.
-- =============================================================================

set_controller_type(1)               -- TOP_DOWN: stick_1 walks the avatar
set_gravity_direction(Vector2(0, 0)) -- top-down: no gravity pull

set_input_display_name("stick_1","{move}")
set_input_display_name("stick_2","{aim}")
set_input_display_name("key_12","{use_attack}")
set_input_display_name("key_9","{interact}")
set_input_display_name("key_6","{inventory}")
set_input_display_name("key_5","{next_item}")
set_input_display_name("key_7","{drop_held_item}")
set_input_display_name("key_11","{map}")

change_view("gameplay")

function update_inputs_label()
    set_label({ name = "_mbl_inputs", text = table.concat({
        "{hint_move_aim}",
        "{hint_use_attack}",
        "{hint_interact}",
        "{hint_inventory_craft}",
        "{hint_next_item}",
        "{hint_drop_held_item}",
        "{hint_map}",
    }, "\n") })
end

function _on_gamepad_connection_changed(has_gamepad)
    update_inputs_label()
end

update_inputs_label()
