singleton_name = "finding_liar_data"

-- Categories and their word sets for Finding Liar game
-- Each category contains multiple possible words, and one will be chosen randomly for each game

local word_categories = {
    -- Location Categories
    {
        name = "Beach",
        words = {
            "sunscreen", "volleyball", "seashell", "sandcastle", "lifeguard", 
            "surfboard", "beach umbrella", "bikini", "flip-flops", "pier"
        }
    },
    {
        name = "Library",
        words = {
            "bookmark", "librarian", "reading room", "book shelf", "study table",
            "quiet zone", "computer terminal", "reference desk", "magazine rack", "checkout counter"
        }
    },
    {
        name = "Restaurant",
        words = {
            "menu", "waiter", "kitchen", "reservation", "appetizer",
            "wine list", "cash register", "dining table", "chef", "tip"
        }
    },
    {
        name = "Hospital",
        words = {
            "stethoscope", "nurse", "surgery", "emergency room", "patient",
            "doctor", "medical chart", "wheelchair", "waiting room", "bandage"
        }
    },
    {
        name = "School",
        words = {
            "blackboard", "homework", "principal", "classroom", "student",
            "teacher", "textbook", "lunch break", "playground", "backpack"
        }
    },
    {
        name = "Airport",
        words = {
            "boarding pass", "security check", "luggage", "departure gate", "pilot",
            "flight attendant", "runway", "passport", "customs", "baggage claim"
        }
    },
    {
        name = "Gym",
        words = {
            "treadmill", "weights", "locker room", "personal trainer", "membership",
            "exercise bike", "yoga mat", "protein shake", "towel", "workout routine"
        }
    },
    {
        name = "Zoo",
        words = {
            "zookeeper", "animal enclosure", "feeding time", "gift shop", "admission ticket",
            "elephant", "tiger", "monkey", "guided tour", "conservation"
        }
    },

    -- Activity Categories
    {
        name = "Camping Trip",
        words = {
            "tent", "campfire", "sleeping bag", "hiking boots", "compass",
            "backpack", "marshmallow", "flashlight", "map", "forest ranger"
        }
    },
    {
        name = "Wedding",
        words = {
            "bride", "groom", "wedding dress", "bouquet", "ceremony",
            "reception", "wedding cake", "photographer", "vows", "honeymoon"
        }
    },
    {
        name = "Birthday Party",
        words = {
            "birthday cake", "candles", "presents", "party hat", "balloons",
            "invitation", "party games", "gift wrap", "birthday song", "celebration"
        }
    },
    {
        name = "Movie Theater",
        words = {
            "movie ticket", "popcorn", "screen", "projector", "theater seat",
            "concession stand", "movie trailer", "box office", "3D glasses", "premiere"
        }
    },

    -- Object Categories  
    {
        name = "Kitchen Items",
        words = {
            "refrigerator", "microwave", "cutting board", "mixing bowl", "spatula",
            "oven", "blender", "coffee maker", "dishwasher", "recipe book"
        }
    },
    {
        name = "Office Supplies",
        words = {
            "stapler", "paper clip", "printer", "computer mouse", "keyboard",
            "filing cabinet", "whiteboard", "desk lamp", "calculator", "notebook"
        }
    },
    {
        name = "Musical Instruments",
        words = {
            "piano", "guitar", "violin", "drums", "trumpet",
            "saxophone", "flute", "harp", "microphone", "music sheet"
        }
    },
    {
        name = "Sports Equipment",
        words = {
            "basketball", "soccer ball", "tennis racket", "golf club", "baseball bat",
            "swimming goggles", "running shoes", "helmet", "jersey", "scoreboard"
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