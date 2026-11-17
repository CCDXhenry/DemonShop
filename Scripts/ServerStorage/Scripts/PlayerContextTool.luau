-- 玩家基础上下文：国家地区失败降级，远程配置显式启用且仅提取声明字段
--!strict
local LocalizationService = game:GetService("LocalizationService")
local ConfigService = game:GetService("ConfigService")
local Config = require(game:GetService("ReplicatedStorage").Scripts.Shared.GameConfig)
local Tool = {}
function Tool.Get(player: Player): (string, Config.PlayerConfigInfo)
	local ok, region = pcall(function(): string
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	local result = table.clone(Config.DefaultPlayerConfig)
	-- AB 版本仅对新于配置版本的玩家生效；在加载资料后单独解析。
	return (if ok then region else "unknown"), result
end
function Tool.ResolveConfig(player: Player, firstVersion: string): Config.PlayerConfigInfo
	local result = table.clone(Config.DefaultPlayerConfig)
	if not Config.RemoteConfigEnabled then
		return result
	end
	local function AtLeast(a: string, b: string): boolean
		local left, right = {}, {}
		for n in a:gmatch("%d+") do
			table.insert(left, tonumber(n) or 0)
		end
		for n in b:gmatch("%d+") do
			table.insert(right, tonumber(n) or 0)
		end
		for i = 1, math.max(#left, #right) do
			if (left[i] or 0) ~= (right[i] or 0) then
				return (left[i] or 0) > (right[i] or 0)
			end
		end
		return true
	end
	local ok, reason = pcall(function(): boolean
		local snapshot = if AtLeast(firstVersion, Config.ABTestVersion) then ConfigService:GetConfigForPlayerAsync(player) else ConfigService:GetConfigAsync()
		for key, default in result do
			local value = snapshot:GetValue(key)
			if
				typeof(value) == typeof(default)
				and (type(value) == "string" or type(value) == "boolean" or (type(value) == "number" and value == value and math.abs(value) < math.huge))
			then
				result[key] = value
			end
		end
		return true
	end)
	if not ok then
		warn("[PlayerContext] Config unavailable", reason)
	end
	return result
end
return Tool
