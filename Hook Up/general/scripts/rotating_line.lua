network_mode = 2
gravity_scale = 0.0
linear_damp = 0.0
angular_damp = -1.0
mass=1000000000000.0
angular_velocity=1.0

-- Değirmen ayarları
rotation_speed = 90.0  -- Derece/saniye
cross_size = 1.0      -- Artı şeklinin boyutu
cross_thickness = 7.0  -- Çizgi kalınlığı

add_tag(name,"rotating_line")

-- Görsel elementler
horizontal_rect_name = ""
vertical_rect_name = ""

size_x=cross_size*32
size_y=cross_thickness*32

collision_config={parent_name=name,shape="rectangle",size=Vector2(size_x,size_y),collision_layer={1},collision_mask={1,2}}
collision_name=set_collision(collision_config)



function create_rotating_cross()
    -- Yatay dikdörtgen (yatay çizgi)
    horizontal_rect_name = set_image({
        parent_name = name,
        image_path = "wood",  -- Beyaz dikdörtgen texture
        size = Vector2(cross_size, cross_thickness),
        is_repeat = true,
        z_index = 5
    })
    

    

end

-- Değirmen oluşturulduğunda çağrılır
create_rotating_cross()




