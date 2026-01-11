area_radius = 48
bounce = 1
friction = 0.1
network_mode = 2
linear_damp = 0.5
singleton_name = "ball"

set_camera_target(name)

navigation_name=set_navigation_icon({--image_path is not set, so it will be arrow
target_name=name,
is_rotate= true,
text="Ball",
outline_color=Color(0,0,0,1),--Black
outline_size=8,
is_show_distance=true,
})
add_tag(name,"ball")
image_config={parent_name=name,image_path="SoccerBall"}
image_name= set_image(image_config)
set_image_pixel(name,image_name,Vector2(16,16))
collision_config={parent_name=name,name=collision_name,shape="circle",size=8}
collision_name=set_collision(collision_config)


init_pos=get_value("",name,"position")
last_touching_steam_id=""
previous_touching_steam_id=""-- For tracking potential assists



function reset() --custom function
    change_instantly({
        entity_name = name,
        angular_velocity = 0.0,
        position = init_pos,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })
end



function handle_goal(scoring_team)
    if last_touching_steam_id == "" then return end
        -- Send goal info to UI manager
        run_network_function("-ui_manager", "handle_goal_ui_ALL", {last_touching_steam_id,previous_touching_steam_id,scoring_team})
        reset()
        run_function("-ui_manager","reset_users_position")
    end

function on_body_body_entered(data)
    if not IS_HOST then return end
        entity_name=data["body_name"]
        if entity_name~= "TileMap" then
            local _script_name = get_value("",entity_name, "script_name")
            if _script_name == "user" then
                local nickname = get_value("", entity_name, "nickname")
                set_last_touching_steam_id(entity_name)-- entity_name is steam_id
            end
        end
    end

function on_body_body_exited(body_name)
end

function on_area_area_entered(area_name)
end

function on_area_area_exited(area_name)
end

function on_body_area_entered(area_name)
if get_value("","-time_manager","is_match_active")==false then
return
end


    if area_name=="red_goalpost"  then
        handle_goal(2)--BLUE
    end
    if area_name=="blue_goalpost"  then
        handle_goal(1)-- RED
    end
end

function on_body_area_exited(area_name)
end



function on_area_body_entered(body_name)
    if body_name == "TileMap" then
        return
    end
    local _script_name= get_value("", body_name, "script_name")

    if  _script_name == "user" then
        run_function(body_name, "set_ball_interactable", {true})
    end
end

function on_area_body_exited(body_name)
    if body_name == "TileMap" then
        return
    end
    local _script_name= get_value("", body_name, "script_name")

    if _script_name=="user" then
        run_function(body_name,"set_ball_interactable",{false})
    end
end



function set_last_touching_steam_id(_steam_id)
    previous_touching_steam_id = last_touching_steam_id
    last_touching_steam_id = _steam_id
end
















