singleton_name = "w"

-- =============================================================================
-- MineBlockLand - one-time world setup (runs once on every peer at map load).
-- Day/night visuals, the clock and everything stateful live in -gm; this file
-- only wires the controller, the HUD view and the input hints.
-- =============================================================================

set_controller_type(1)               -- TOP_DOWN: stick_1 walks the avatar
set_gravity_direction(Vector2(0, 0)) -- top-down: no gravity pull

set_input_display_name("stick_1", "Move")
set_input_display_name("stick_2", "Aim")
set_input_display_name("key_12", "Use / Attack")
set_input_display_name("key_9", "Interact")
set_input_display_name("key_6", "Inventory")
set_input_display_name("key_5", "Next Item")

change_view("gameplay")

function update_inputs_label()
    set_label({ name = "_mbl_inputs", text = table.concat({
        "@stick_1@ Move   @stick_2@ Aim",
        "@key_12@ Use / Attack",
        "@key_9@ Interact (plant - harvest - eat)",
        "@key_6@ Inventory & Craft",
        "@key_5@ Next Item",
    }, "\n") })
end

function _on_gamepad_connection_changed(has_gamepad)
    update_inputs_label()
end

update_inputs_label()
