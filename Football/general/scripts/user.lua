bounce = 0.8
friction = 0.1
lock_rotation = true

add_tag(name,"user")
collision_name=""


--last inputs
is_hit_ball_input_last=false
is_sprint_input_last=false
is_dash_input_last=false

-- visuals
image_name=""
nickname_label_name=""
hit_progres_bar_name=""
interact_label_name=""

--general values
hit_value=0
is_ball_interactable=false
init_pos=get_value("",name,"position")

team=0-- 0 spectator 1 red 2 blue
is_avatar_loaded=false
print("team: "..tostring(team).." nickname: "..nickname)
function reset_position()
    if IS_HOST then
        new_position=Vector2(0,0)
        if team==1 then
            new_position=get_random_position_in_polygon("red_spawn_area")
        else
            new_position=get_random_position_in_polygon("blue_spawn_area")
        end
        change_instantly({
            entity_name = name,
            angular_velocity = 0.0,
            position = new_position,
            linear_velocity = Vector2(0, 0),
            rotation = 0.0
        })
    end
end

function delete_visuals()
    if hit_progres_bar_name ~= "" then
        destroy(name,hit_progres_bar_name)
        hit_progres_bar_name = ""
    end
    if nickname_label_name ~= "" then
        destroy(name,nickname_label_name)
        nickname_label_name = ""
    end
    if interact_label_name ~= "" then
        destroy("",interact_label_name)
        interact_label_name = ""
    end
    if image_name ~= "" then
        destroy(name,image_name)
        image_name = ""
    end
    if collision_name ~= "" then
        destroy(name,collision_name)
        collision_name = ""
    end
end

function change_team_ALL(sender_id,_team)
    team=_team
    if _team == 0 then-- Spectator
		if IS_LOCAL then
        	set_camera_target("*ball")
		end
        delete_visuals()
        return
    end
    reset_position()
    collision_config={parent_name=name,name=collision_name,shape="circle",size=16}
    collision_name=set_collision(collision_config)
	if IS_LOCAL then
       	set_camera_target(name)
	end
    nickname_config={parent_name=name,name=nickname_label_name,text=nickname,position=Vector2(-256,16),size=Vector2(512,16),horizontal_alignment=1,vertical_alignment=1}
    nickname_label_name=set_label(nickname_config)
    if is_avatar_loaded then
        image_name= set_image({parent_name=name,name=image_name,image_path=name})-- name in user entity is steam_id and path of avatar image
    else
        image_name= set_image({parent_name=name,name=image_name})--just temporary image until avatar is loaded
    end
    set_image_pixel(name,image_name,Vector2(32,32))-- fit to 32 width 32 height pixels

    color=Color(1,1,1,1)
    if team==1 then--RED
        color=Color(1,0,0,1)
    else
        color=Color(0,0,1,1)--BLUE
    end
    set_shader({parent_name= name,image_name= image_name, shader_name= "circle",outline_color= color})--default values inner_circle=0.45 outer_circle=0.49 smoothness=0.01

    if IS_LOCAL then
        config={parent_name=name,name=hit_progres_bar_name,position=Vector2(-64,48),modulate=Color(1,1,0,1),size=Vector2(128,16)}
        hit_progres_bar_name=set_progress_bar(config)
        interact_label_name=set_label({position=Vector2(0,16),name=interact_label_name})
    end
end

function _process(delta,inputs)
    if team == 0 then
        return
    end
    is_hit_ball_input_new=inputs["key_6"]
    if is_hit_ball_input_new then--while pressing
        hit_value = math.min(hit_value + 100*delta, 100)
    end

    if IS_LOCAL then
        config={parent_name=name,name=hit_progres_bar_name,value=hit_value}
        set_progress_bar(config)

        if is_ball_interactable then
            ball_pos = get_value("","*ball","position")
            interaction_config={text="Press @key_6@",position=ball_pos+Vector2(-64,32),name=interact_label_name}
            set_label(interaction_config)
        else
            interaction_config={text="",name=interact_label_name}
            set_label(interaction_config)
        end
    end

    if  is_hit_ball_input_last==true and is_hit_ball_input_new == false then --just released
        hit_ball()
    end
    is_hit_ball_input_last=is_hit_ball_input_new

    is_sprint_input_new=inputs["key_10"]
    if IS_HOST and  is_sprint_input_new == true then
    end
    is_sprint_input_last=is_sprint_input_new

    return inputs
end

function set_ball_interactable(state)
    is_ball_interactable=state
end


function _on_loaded_avatar(steam_id) 
    if name==steam_id then -- if it is this user entity
        is_avatar_loaded=true
        if team==0 then-- if spectator dont need to set image
            return
        end
        image_config={parent_name=name,image_path=steam_id}
        image_name= set_image(image_config)
        set_image_pixel(name,image_name,Vector2(32,32))
        color=Color(1,1,1,1)
        if team==1 then--RED
            color=Color(1,0,0,1)
        else
            color=Color(0,0,1,1)--BLUE
        end
        set_shader({parent_name= name,image_name= image_name, shader_name= "circle",outline_color= color})
    end
end

function normalize_vector2(vector)
    len= math.sqrt(vector.x * vector.x + vector.y * vector.y)
    new_vector2=Vector2(0,0)
    new_vector2.x = vector.x / len
    new_vector2.y = vector.y / len
    return new_vector2
end

function hit_ball()
    if IS_HOST  and is_ball_interactable then
        ball_pos= get_value("","*ball","position")
        pos= get_value("",name,"position")
        dif=ball_pos-pos
        way=normalize_vector2(dif)
        new_vel=way* 3.0 *hit_value -- Linear velocity magnitude is capped at 300 for all objects; values above are unnecessary.  3.0 multiply 100 (max value of hit_value) is 300
        run_function("*ball", "set_last_touching_steam_id", {name})-- name of user is steam_id
        add_linear_velocity("*ball",new_vel)
    end
    hit_value=0
end

function on_body_body_entered(data) -- data have name,position if collided with map it also have tile_id and tile_position
end

function go_to_spawn_position()
    set_value("",name,"position",init_pos)
    set_value("",name,"linear_velocity",Vector2(0,0))
end

function on_area_area_entered(area_name)
end

function on_area_area_exited(area_name)
end

function on_area_body_entered(body_name)
end

function on_area_body_exited(body_name)
end

function on_body_body_exited(body_name)
end

