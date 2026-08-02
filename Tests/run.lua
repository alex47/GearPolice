local scriptPath = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."
local projectRoot = testsDirectory:match("^(.*)[/\\]Tests$") or "."

local Harness = assert(loadfile(testsDirectory .. "/TestHarness.lua"))()
local suite = Harness.New(projectRoot)

local testFiles = {
    "AutomaticGroupScanTests.lua",
    "GearStandardsTests.lua",
    "IdentityProblemsTests.lua",
    "RosterWhisperTests.lua",
    "CommsConstantsTests.lua",
}

for _, testFile in ipairs(testFiles) do
    local registerTests = assert(loadfile(testsDirectory .. "/" .. testFile))()
    registerTests(Harness, suite)
end

if not Harness.Run(suite) then
    os.exit(1)
end
