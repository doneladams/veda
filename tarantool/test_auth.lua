local test_auth = {}

function test_auth.test()
  --  net_box = require('net.box')
   -- connection = net_box:new(3308)
    require("authorize")
    io.input("acl.log")
    count = 0
    incorrect_count = 0
    tests = {}
    tests_rights = {}
    while true do
        local line = io.read()
        if line == nil then 
            break 
        end
        if count % 100000 == 0 and count > 0 then
            print(count)
        end

        if count == 2000000 then
            break
        end

        arr = {}
        j = 0
        for arg in string.gmatch(line, "%S+") do
            arr[j] = arg
            j=j+1   
        end

        real_rights = 0
        if j > 2 then
            for k=j-1,2,-1 do
                if arr[k] == "C" then
                    real_rights = real_rights + 1
                elseif arr[k] == "R" then
                    real_rights = real_rights + 2
                elseif arr[k] == "U" then
                    real_rights = real_rights + 4
                else
                    real_rights = real_rights + 8
                end
            end
        end
        tests[count] = {}
        tests[count][0] = arr[0]
        tests[count][1] = arr[1]
        tests_rights[count] = real_rights
        count = count + 1
    end 
    i = 0
    print("count="..count)
    right_count = 0

    current_clock = os.clock()
    for i=0,count-1,1 do
        ret_code = authorize("M"..tests[i][0], "M"..tests[i][1])

        if tests_rights[i] ~= ret_code then
            print("M"..tests[i][0].." ".."M"..tests[i][1].." "..tests_rights[i])
            print(ret_code)
            print(tests_rights[i])
            print(count)
            print("incorrect")
            break
            --incorrect_count = incorrect_count + 1
        end

        if i % 50000 == 0 then
            print(i)
            print(50000 / (os.clock() - current_clock))
            current_clock = os.clock()
        end
    end

--[[    ret_code = authorize("Mcfg:VedaSystem", "Mcfg:")
    print(ret_code)]]
end
return test_auth