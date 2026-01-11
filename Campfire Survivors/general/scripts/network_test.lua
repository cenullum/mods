
-- Network test functions
function test_host_function_HOST(sender_id, test_param)
    print("HOST function called")
    print("Sender ID:", sender_id)
    print("Test param:", test_param)
    print("IS_HOST:", IS_HOST)
end

function test_client_function_CLIENT(sender_id, test_param)
    print("CLIENT function called")
    print("Sender ID:", sender_id)
    print("Test param:", test_param)
    print("IS_HOST:", IS_HOST)
end

function test_all_function_ALL(sender_id, test_param)
    print("ALL function called")
    print("Sender ID:", sender_id)
    print("Test param:", test_param)
    print("IS_HOST:", IS_HOST)
end

-- Test function to trigger all network functions
function start_test()
    print("start_test")
    if IS_HOST then
        -- Test _HOST function (client -> host)
        run_network_function(name, "test_host_function_HOST", {"host_test_param"})

        -- Test _CLIENT function (host -> all clients)
        run_network_function(name, "test_client_function_CLIENT", {"client_test_param"})

        -- Test _ALL function (host -> all including self)
        run_network_function(name, "test_all_function_ALL", {"all_test_param"})
    else
        -- Test _HOST function (client -> host)
        run_network_function(name, "test_host_function_HOST", {"host_test_param"})
    end
end

-- Panel functions
function create_test_panel()
    panel_name= create_panel({
    title = "Network Test Panel",
    size = Vector2(300, 200),
    position = Vector2(500, 300)
    })

    add_button_to_panel(panel_name,{
    text = "Run Network Tests",
	entity_name=name,
    function_name = "start_test"
    })
end

create_test_panel()









