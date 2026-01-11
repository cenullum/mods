
function format_unix_time(unix_time)
    -- Constants for time calculations
    local SECONDS_PER_MINUTE = 60
    local SECONDS_PER_HOUR = 3600
    local SECONDS_PER_DAY = 86400
    local DAYS_PER_YEAR = 365
    local EPOCH_YEAR = 1970
    
    -- Month data
    local MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    local MONTH_NAMES = {
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    }

    -- Extract time components
    local days = math.floor(unix_time / SECONDS_PER_DAY)
    local seconds_today = unix_time % SECONDS_PER_DAY
    local hours = math.floor(seconds_today / SECONDS_PER_HOUR)
    local minutes = math.floor((seconds_today % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
    local seconds = seconds_today % SECONDS_PER_MINUTE

    -- Calculate year
    local year = EPOCH_YEAR
    local days_remaining = days
    while days_remaining >= DAYS_PER_YEAR do
        if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
            if days_remaining >= 366 then
                days_remaining = days_remaining - 366
                year = year + 1
            else
                break
            end
        else
            days_remaining = days_remaining - 365
            year = year + 1
        end
    end

    -- Calculate month
    local month = 1
    for i, month_length in ipairs(MONTH_DAYS) do
        if days_remaining < month_length then
            month = i
            break
        end
        days_remaining = days_remaining - month_length
    end

    -- Calculate day
    local day = math.floor(days_remaining) + 1

    -- Format time components with leading zeros
    local format_number = function(num)
        return num < 10 and "0" .. num or tostring(num)
    end

    -- Build the final string
    return string.format("%s %d, %d %s:%s:%s",
        MONTH_NAMES[month],
        day,
        year,
        format_number(hours),
        format_number(minutes),
        format_number(seconds)
    )
end





print(format_unix_time(get_os_time()))-- THIS WRITES CURRENT TIME AS ENGLISH


function _on_user_kicked(steam_id,nickname, reason)
    if reason and reason ~= "" then
        add_to_chat("User " .. nickname .. " was KICKED: " .. reason)
    else
        add_to_chat("User " .. nickname .. " was KICKED")
    end
end


function _on_user_banned(steam_id, nickname, duration, reason)
    local unban_time = format_duration(duration)--duration is unix number
	
    if reason and reason ~= "" then
        add_to_chat("User " .. nickname .. " was BANNED until " .. unban_time .. "\nReason: " .. reason)
    else
        add_to_chat("User " .. nickname .. " was BANNED until " .. unban_time)
    end
end



function format_duration(seconds)
    -- Time constants
    local HOUR = 3600
    local DAY = HOUR * 24
    local WEEK = DAY * 7
    local MONTH = DAY * 30
    local YEAR = DAY * 365
    
    -- If less than 1 hour, return "1 Hour"
    if seconds < HOUR then
        return "1 Hour"
    end
    
    -- Calculate time components
    local years = math.floor(seconds / YEAR)
    seconds = seconds % YEAR
    
    local months = math.floor(seconds / MONTH)
    seconds = seconds % MONTH
    
    local weeks = math.floor(seconds / WEEK)
    seconds = seconds % WEEK
    
    local days = math.floor(seconds / DAY)
    seconds = seconds % DAY
    
    local hours = math.floor(seconds / HOUR)
    
    -- Build duration string
    local parts = {}
    
    if years > 0 then
        parts[#parts + 1] = years .. (years == 1 and " Year" or " Years")
    end
    
    if months > 0 then
        parts[#parts + 1] = months .. (months == 1 and " Month" or " Months")
    end
    
    if weeks > 0 then
        parts[#parts + 1] = weeks .. (weeks == 1 and " Week" or " Weeks")
    end
    
    if days > 0 then
        parts[#parts + 1] = days .. (days == 1 and " Day" or " Days")
    end
    
    if hours > 0 then
        parts[#parts + 1] = hours .. (hours == 1 and " Hour" or " Hours")
    end
    
    -- Join parts with commas and "and"
    if #parts == 0 then
        return "1 Hour"
    elseif #parts == 1 then
        return parts[1]
    else
        local last = table.remove(parts)
        return table.concat(parts, ", ") .. " and " .. last
    end
end



