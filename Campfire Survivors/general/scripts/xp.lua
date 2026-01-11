network_mode = 1

add_tag(name,"xp")
image_name=set_image({parent_name=name,image_path="xp"})

area_config={
parent_name=name,
shape="circle",
size=16,
collision_layer = {2},
collision_mask = {2}
}
set_area(area_config)

-- Auto-destroy after 30 seconds if not collected
--run_function(name, "destroy_self", {}, 30.0)

function destroy_self()
    destroy("", name)
end