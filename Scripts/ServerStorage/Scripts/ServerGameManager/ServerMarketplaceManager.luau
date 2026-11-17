-- 商城基础管理器：校验配置通行证；没有交付处理器的商品不确认收据
--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage").Scripts.Shared
local Config = require(Shared.GameConfig)
local Lifecycle = require(Shared.LifecycleTool)
local Info = require(script.Parent.Parent.ServerGameInfo)
local Analytics = require(script.Parent.Parent.AnalyticsTool)
local Manager = {}
Manager.__index = Manager
export type ReceiptInfo = { PlayerId: number, ProductId: number, PurchaseId: string }
export type Manager = typeof(setmetatable({} :: {
 scope: Lifecycle.Lifecycle?,
 receiptCallback: ((ReceiptInfo) -> Enum.ProductPurchaseDecision)?,
}, Manager))
local function Configured(id: number): boolean
 for _, configured in Config.GamePassId do if configured == id then return true end end
 return false
end
function Manager.ProcessReceipt(_receipt: ReceiptInfo): Enum.ProductPurchaseDecision
 return Enum.ProductPurchaseDecision.NotProcessedYet
end
function Manager.new(): Manager return setmetatable({ scope = nil, receiptCallback = nil }, Manager) end
function Manager.CheckOwnedGamePasses(self: Manager, player: Player): ()
 local scope = self.scope
 if not scope then return end
 scope:Spawn(function(): ()
  for _, id in Config.GamePassId do
   if not scope.alive or not Info.IsActive(player) then return end
   local ok, owned = pcall(function(): boolean return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id) end)
   if ok and owned and scope.alive and Info.IsActive(player) then Info.SetPlayerGamePassAcquired(player, id) end
  end
 end)
end
function Manager.Init(self: Manager): ()
 if self.scope then return end
 local scope = Lifecycle.new()
 self.scope = scope
 scope:Connect(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Instance, id: number, purchased: boolean): ()
  if purchased and player:IsA("Player") and Configured(id) and Info.SetPlayerGamePassAcquired(player, id) then Analytics.AddPassPurchaseEvent(player, id, Config.GamePassPrice[id]) end
 end))
 -- Roblox 的 ProcessReceipt 是只写回调，不能读取；该入口为本项目唯一安装点。
 local callback = Manager.ProcessReceipt
 self.receiptCallback = callback
 MarketplaceService.ProcessReceipt = callback
end
function Manager.Destroy(self: Manager): ()
 if self.scope then self.scope:Destroy(); self.scope = nil end
 MarketplaceService.ProcessReceipt = Manager.ProcessReceipt
 self.receiptCallback = nil
end
export type ServerMarketplaceManager = Manager
return Manager
