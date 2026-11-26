-- 把武器挥击表现和范围攻击模板写入 GameModels.rbxm
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local source = fs.readFile("Tools/Gameplay/build-weapon-presentation.luau")
local cut = string.find(source, "\nlocal function Run", 1, true)
assert(cut, "builder footer missing")
local chunk = luau.load(string.sub(source, 1, cut - 1) .. "\nreturn Build\n", {
	environment = {
		Instance = roblox.Instance,
		CFrame = roblox.CFrame,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		assert = assert,
		math = math,
		tostring = tostring,
		type = type,
		typeof = typeof,
		ipairs = ipairs,
		pairs = pairs,
		string = string,
		table = table,
		print = print,
	},
})
local build = chunk()
local path = "Assets/Models/GameModels.rbxm"
local roots = roblox.deserializeModel(fs.readFile(path))
assert(#roots == 1 and roots[1].Name == "Models", "GameModels.rbxm must contain one Models root")
local summary = build(roots[1])
fs.writeFile(path, roblox.serializeModel(roots))
print(summary)
