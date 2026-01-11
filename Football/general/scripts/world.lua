set_controller_type(1) --topdown
set_gravity_direction(Vector2(0,0))
set_camera_zoom(Vector2(2,2))



set_input_display_name("stick_1","Movement")
set_input_display_name("key_6","Hit Ball")
set_input_display_name("key_7","Dash")
set_input_display_name("key_10","Sprint")
set_input_display_name("key_11","Score Table")

set_value("","_USQKTEW3zusL1CNU1737417431","text","@key_6@ Hit Ball\n@key_11@ Scoreboard\n@stick_1@ Movement")-- right bottom  inputs label

function _on_gamepad_connection_changed(has_gamepad)
    -- Update inputs
	set_value("","_USQKTEW3zusL1CNU1737417431","text","@key_6@ Hit Ball\n@key_11@ Scoreboard\n@stick_1@ Movement")
end



set_audio({
stream_path = "ambient",
bus = "Ambient",
is_2d=false,
is_loop=true
})

destroy("","information")-- this is warning label for For more accurate physics, polygon collision is used instead of tilemap collision.
destroy("","information2")
-- transparent color for polygons
set_value("","OMeyT7xukFzoOvQa1738604217","modulate",Color(0,0,0,0))
set_value("","qr0p3oNN4dlez2T81738603694","modulate",Color(0,0,0,0))
set_value("","DSpQaO3egCMaF8B91738602835","modulate",Color(0,0,0,0))
set_value("","lVVsqT71oBpRoRzU1738604212","modulate",Color(0,0,0,0))



