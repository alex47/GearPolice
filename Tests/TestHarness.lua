local Harness = {}

function Harness.New(projectRoot)
    return {
        projectRoot = projectRoot,
        tests = {},
        passed = 0,
        failed = 0,
    }
end

function Harness.Add(suite, name, testFunction)
    table.insert(suite.tests, {
        name = name,
        run = testFunction,
    })
end

function Harness.AssertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

function Harness.AssertFalse(value, message)
    if value then
        error(message or "expected a false value", 2)
    end
end

function Harness.AssertEqual(expected, actual, message)
    if expected ~= actual then
        error(
            (message and message .. ": " or "")
                .. "expected " .. tostring(expected) .. ", got " .. tostring(actual),
            2
        )
    end
end

function Harness.MakeEnvironment(values)
    local environment = values or {}
    environment._G = environment
    return setmetatable(environment, {
        __index = _G,
    })
end

function Harness.LoadModule(suite, environment, relativePath)
    local chunk, loadError = loadfile(suite.projectRoot .. "/" .. relativePath)
    if not chunk then
        error(loadError, 2)
    end

    setfenv(chunk, environment)
    return chunk()
end

function Harness.Run(suite)
    for _, test in ipairs(suite.tests) do
        local succeeded, testError = xpcall(test.run, debug.traceback)
        if succeeded then
            suite.passed = suite.passed + 1
            print("PASS " .. test.name)
        else
            suite.failed = suite.failed + 1
            print("FAIL " .. test.name)
            print(testError)
        end
    end

    print(("%d passed, %d failed"):format(suite.passed, suite.failed))
    return suite.failed == 0
end

return Harness
