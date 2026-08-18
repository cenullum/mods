singleton_name = "finding_liar_data"

-- Categories and their word sets for Finding Liar game
-- Each category contains multiple possible words, and one will be chosen randomly for each game

local word_categories = {
    {
        name = "{cat_occupation}",
        words = {
            "{w_doctor}", "{w_teacher}", "{w_engineer}", "{w_lawyer}", "{w_chef}", 
            "{w_police_officer}", "{w_firefighter}", "{w_pilot}", "{w_nurse}", "{w_farmer}",
            "{w_architect}", "{w_dentist}", "{w_painter}", "{w_musician}", "{w_writer}"
        }
    },
    {
        name = "{cat_item}",
        words = {
            "{w_table}", "{w_chair}", "{w_television}", "{w_refrigerator}", "{w_lamp}",
            "{w_computer}", "{w_phone}", "{w_clock}", "{w_book}", "{w_cup}",
            "{w_fork}", "{w_spoon}", "{w_knife}", "{w_plate}", "{w_towel}"
        }
    },
    {
        name = "{cat_place}",
        words = {
            "{w_school}", "{w_hospital}", "{w_library}", "{w_restaurant}", "{w_airport}",
            "{w_park}", "{w_museum}", "{w_cinema}", "{w_theater}", "{w_beach}",
            "{w_market}", "{w_pharmacy}", "{w_bank}", "{w_post_office}", "{w_gym}"
        }
    },
    {
        name = "{cat_animal}",
        words = {
            "{w_cat}", "{w_dog}", "{w_lion}", "{w_elephant}", "{w_giraffe}",
            "{w_monkey}", "{w_bear}", "{w_wolf}", "{w_rabbit}", "{w_bird}",
            "{w_snake}", "{w_fish}", "{w_horse}", "{w_cow}", "{w_sheep}"
        }
    },
    {
        name = "{cat_vehicle}",
        words = {
            "{w_car}", "{w_bus}", "{w_bicycle}", "{w_motorcycle}", "{w_train}",
            "{w_airplane}", "{w_ship}", "{w_truck}", "{w_tractor}", "{w_helicopter}",
            "{w_subway}", "{w_tram}", "{w_scooter}", "{w_yacht}", "{w_speedboat}"
        }
    }
}

-- Function to get a random category
function get_random_category()
    local random_index = math.random(1, #word_categories)
    return word_categories[random_index]
end

-- Function to get all categories (for testing or admin features)
function get_all_categories()
    return word_categories
end

-- Function to get category by name
function get_category_by_name(category_name)
    for _, category in ipairs(word_categories) do
        if category.name == category_name then
            return category
        end
    end
    return nil
end

-- Function to get total number of categories
function get_categories_count()
    return #word_categories
end 