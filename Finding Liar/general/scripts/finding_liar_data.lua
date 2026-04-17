singleton_name = "finding_liar_data"

-- Categories and their word sets for Finding Liar game
-- Each category contains multiple possible words, and one will be chosen randomly for each game

local word_categories = {
    {
        name = "occupation",
        words = {
            "Doctor", "Teacher", "Engineer", "Lawyer", "Chef", 
            "Police Officer", "Firefighter", "Pilot", "Nurse", "Farmer",
            "Architect", "Dentist", "Painter", "Musician", "Writer"
        }
    },
    {
        name = "item",
        words = {
            "Table", "Chair", "Television", "Refrigerator", "Lamp",
            "Computer", "Phone", "Clock", "Book", "Cup",
            "Fork", "Spoon", "Knife", "Plate", "Towel"
        }
    },
    {
        name = "place",
        words = {
            "School", "Hospital", "Library", "Restaurant", "Airport",
            "Park", "Museum", "Cinema", "Theater", "Beach",
            "Market", "Pharmacy", "Bank", "Post Office", "Gym"
        }
    },
    {
        name = "animal",
        words = {
            "Cat", "Dog", "Lion", "Elephant", "Giraffe",
            "Monkey", "Bear", "Wolf", "Rabbit", "Bird",
            "Snake", "Fish", "Horse", "Cow", "Sheep"
        }
    },
    {
        name = "vehicle",
        words = {
            "Car", "Bus", "Bicycle", "Motorcycle", "Train",
            "Airplane", "Ship", "Truck", "Tractor", "Helicopter",
            "Subway", "Tram", "Scooter", "Yacht", "Speedboat"
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