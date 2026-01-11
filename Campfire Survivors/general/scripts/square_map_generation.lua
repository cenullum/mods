-- Function to draw a rectangle using tiles
-- x, y: top-left position of the rectangle
-- width, height: dimensions of the rectangle
-- use_middle_tile: if true, places a single (4,1) tile in the exact center of the rectangle
function draw_rectangle(x, y, width, height, use_middle_tile)
    -- Validate parameters
    if width < 2 or height < 2 then
        print("Error: Width and height must be at least 2")
        return
    end

    -- If use_middle_tile is nil, set it to false (default parameter value)
    if use_middle_tile == nil then
        use_middle_tile = false
    end

    -- Draw the four corners
    -- Top-left corner
    set_tile(x, y, Vector2(0, 0))

    -- Top-right corner
    set_tile(x + width - 1, y, Vector2(2, 0))

    -- Bottom-left corner
    set_tile(x, y + height - 1, Vector2(0, 2))

    -- Bottom-right corner
    set_tile(x + width - 1, y + height - 1, Vector2(2, 2))

    -- Draw top and bottom edges
    for i = 1, width - 2 do
        -- Top edge
        set_tile(x + i, y, Vector2(1, 0))

        -- Bottom edge
        set_tile(x + i, y + height - 1, Vector2(1, 2))
    end

    -- Draw left and right edges
    for j = 1, height - 2 do
        -- Left edge
        set_tile(x, y + j, Vector2(0, 1))

        -- Right edge
        set_tile(x + width - 1, y + j, Vector2(2, 1))
    end

    -- Fill the interior with regular tiles (1,1)
    for i = 1, width - 2 do
        for j = 1, height - 2 do
            set_tile(x + i, y + j, Vector2(1, 1))
        end
    end

    -- If requested, place a single special tile (4,1) in the exact center
    if use_middle_tile and width >= 3 and height >= 3 then
        -- Calculate the center position
        local center_x = x + math.floor(width / 2)
        local center_y = y + math.floor(height / 2)

        -- Place the special middle tile
        pos=map_to_local(Vector2(center_x,center_y))
        set_value("","-campfire","position",pos)

    end

    print("Rectangle drawn at (" .. x .. ", " .. y .. ") with dimensions " .. width .. "x" .. height)
end

-- Example usage:
-- Draw a 5x4 rectangle at position (10, 10) with regular interior
-- draw_rectangle(10, 10, 5, 4, false)

 info=run_function("-mg", "get_info")

draw_rectangle(info.rectangle_x, info.rectangle_y, info.rectangle_width,info.rectangle_height, true)

