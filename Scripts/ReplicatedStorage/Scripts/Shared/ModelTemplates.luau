-- 运行时模型模板索引：按分类子目录读取 ReplicatedStorage.Models 下的唯一实例来源
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelTemplates = {}

export type Category = "Characters" | "Weapons" | "CarryRigs" | "Items" | "Effects" | "Previews"

ModelTemplates.Categories = {
	"Characters",
	"Weapons",
	"CarryRigs",
	"Items",
	"Effects",
	"Previews",
} :: { Category }

function ModelTemplates.GetRoot(): Folder?
	local root = ReplicatedStorage:FindFirstChild("Models")
	return if root and root:IsA("Folder") then root else nil
end

function ModelTemplates.WaitRoot(): Folder
	local root = ReplicatedStorage:WaitForChild("Models")
	assert(root:IsA("Folder"), "ReplicatedStorage.Models must be a Folder")
	return root
end

function ModelTemplates.GetCategory(category: Category): Folder?
	local root = ModelTemplates.GetRoot()
	local folder = if root then root:FindFirstChild(category) else nil
	return if folder and folder:IsA("Folder") then folder else nil
end

function ModelTemplates.WaitCategory(category: Category): Folder
	local folder = ModelTemplates.WaitRoot():WaitForChild(category)
	assert(folder:IsA("Folder"), "Missing ReplicatedStorage.Models." .. category)
	return folder
end

function ModelTemplates.Find(category: Category, name: string): Instance?
	local folder = ModelTemplates.GetCategory(category)
	return if folder then folder:FindFirstChild(name) else nil
end

function ModelTemplates.Wait(category: Category, name: string): Instance
	return ModelTemplates.WaitCategory(category):WaitForChild(name)
end

function ModelTemplates.FindCharacter(name: string): Model?
	local template = ModelTemplates.Find("Characters", name)
	return if template and template:IsA("Model") then template else nil
end

function ModelTemplates.WaitCharacter(name: string): Model
	local template = ModelTemplates.Wait("Characters", name)
	assert(template:IsA("Model"), "Character template must be a Model: " .. name)
	return template
end

function ModelTemplates.FindWeapon(name: string): Tool?
	local template = ModelTemplates.Find("Weapons", name)
	return if template and template:IsA("Tool") then template else nil
end

function ModelTemplates.FindCarryRig(name: string): Model?
	local template = ModelTemplates.Find("CarryRigs", name)
	return if template and template:IsA("Model") then template else nil
end

function ModelTemplates.FindItem(name: string): Tool?
	local template = ModelTemplates.Find("Items", name)
	return if template and template:IsA("Tool") then template else nil
end

function ModelTemplates.WaitItem(name: string): Tool
	local template = ModelTemplates.Wait("Items", name)
	assert(template:IsA("Tool"), "Item template must be a Tool: " .. name)
	return template
end

function ModelTemplates.FindTool(name: string): Tool?
	return ModelTemplates.FindWeapon(name) or ModelTemplates.FindItem(name)
end

function ModelTemplates.FindEffect(name: string): Model?
	local template = ModelTemplates.Find("Effects", name)
	return if template and template:IsA("Model") then template else nil
end

function ModelTemplates.WaitEffect(name: string): Model
	local template = ModelTemplates.Wait("Effects", name)
	assert(template:IsA("Model"), "Effect template must be a Model: " .. name)
	return template
end

function ModelTemplates.FindPreview(name: string): Model?
	local template = ModelTemplates.Find("Previews", name)
	return if template and template:IsA("Model") then template else nil
end

function ModelTemplates.WaitViewportWorld(): WorldModel
	local world = ModelTemplates.Wait("Previews", "ViewportWorld")
	assert(world:IsA("WorldModel"), "Previews.ViewportWorld must be a WorldModel")
	return world
end

function ModelTemplates.CollectPreloadable(assets: { Instance }, templates: { Instance }): boolean
	local root = ModelTemplates.GetRoot()
	if not root then
		return false
	end
	for _, category in ModelTemplates.Categories do
		local folder = root:FindFirstChild(category)
		if folder and folder:IsA("Folder") and folder.Archivable then
			for _, child in folder:GetChildren() do
				if child.Archivable and (child:IsA("Model") or child:IsA("Tool")) then
					table.insert(assets, child)
					table.insert(templates, child)
				end
			end
		end
	end
	return true
end

return ModelTemplates
