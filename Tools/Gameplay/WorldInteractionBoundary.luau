-- 世界提示离线边界：仅替换原生提示事件、翻译、网络与事件批次调度
local B = {requests={}, translations={}, deferred={}, time=10}
function B.Signal()
	local callbacks={}
	return {
		Connect=function(_,callback) callbacks[callback]=true; return {Disconnect=function() callbacks[callback]=nil end} end,
		Fire=function(_,...) for callback in callbacks do callback(...) end end,
		Count=function() local n=0;for _ in callbacks do n+=1 end;return n end,
	}
end
local function createPrompt()
	local prompt={Enabled=false, MaxActivationDistance=8}
	function prompt:IsA(className) return className == "ProximityPrompt" end
	for _,name in {'PromptButtonHoldBegan','PromptButtonHoldEnded','PromptHidden','Triggered'} do prompt[name]=B.Signal() end
	function prompt:Destroy() self.Parent=nil;self.destroyed=true end
	function prompt:Clone() return createPrompt() end
	return prompt
end
local template = createPrompt()
local uiFolder = {
	WaitForChild = function(_, name) return template end,
	FindFirstChild = function(_, name) return if name == "WorldInteractionPrompt" then template else nil end,
}
B.CreatePrompt = createPrompt
B.ReplicatedStorage={
	UI=uiFolder,
	FindFirstChild=function(_, name) return if name == "UI" then uiFolder else nil end,
	WaitForChild=function(_, name) return if name == "UI" then uiFolder else nil end,
}
B.Net={FireRequest=function(request)table.insert(B.requests,request)end}
B.TranslationTool={
	CustomAutoLocalizeProximityPrompt=function(prompt,action,_,_,object) B.translations[prompt]=true;prompt.ActionText=action;prompt.ObjectText=object end,
	RemoveCustomAutoLocalizeGui=function(prompt)B.translations[prompt]=nil end,
}
B.task={defer=function(callback)table.insert(B.deferred,callback)end}
B.os={clock=function()return B.time end}
function B.Flush() local batch=B.deferred;B.deferred={};for _,callback in batch do callback() end end
return B
