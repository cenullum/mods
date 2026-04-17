singleton_name = "w"

-- Side-scroller setup
set_controller_type(2)
set_gravity_direction(Vector2(0, 1))
set_camera_zoom(Vector2(2.0, 2.0))

set_input_display_name("stick_1", "Movement")
set_input_display_name("key_8", "Jump")

-- Change to gameplay view
change_view("gameplay")

local input_label_id = "_ady8ikljgF1nd4VI1776452312"
local input_text = "@stick_1@ Movement\n@key_8@ Jump"

set_value("", input_label_id, "text", input_text)

function _on_gamepad_connection_changed(has_gamepad)
    set_value("", input_label_id, "text", input_text)
end
