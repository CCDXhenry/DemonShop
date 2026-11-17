-- GUI 离线边界：只替换引擎节点、信号与 Tween，窗口管理器执行正式源码
local B=require('./FoundationBoundary')
local U={Enum=B.Enum,TweenInfo={new=function() return {} end},messages={},sounds=0}
local methods={}
local mt={}
function mt.__index(self,key) return methods[key] or self.props[key] end
function mt.__newindex(self,key,value)
 if key=='Parent' then
  local old=self.props.Parent
  if old then local index=table.find(old.children,self);if index then table.remove(old.children,index) end end
  self.props.Parent=value
  if value then
   table.insert(value.children,self)
   local ancestor=value
   while ancestor do ancestor.DescendantAdded:Fire(self);ancestor=ancestor.Parent end
  end
 else self.props[key]=value end
end
function U.Node(name,class)
 return setmetatable({props={Name=name,ClassName=class,ZIndex=1,Visible=true,Active=true,attributes={},Destroying=B.Signal(),DescendantAdded=B.Signal(),Activated=B.Signal(),MouseEnter=B.Signal(),MouseLeave=B.Signal()},children={}},mt)
end
function methods:IsA(class) return self.ClassName==class or (class=='GuiObject' and (self.ClassName=='Frame' or self.ClassName=='ImageButton' or self.ClassName=='TextLabel')) or (class=='GuiButton' and self.ClassName=='ImageButton') end
function methods:FindFirstChild(name) for _,c in self.children do if c.Name==name then return c end end end
function methods:FindFirstChildOfClass(class) for _,c in self.children do if c.ClassName==class then return c end end end
function methods:WaitForChild(name) local child=self:FindFirstChild(name);assert(child,name);return child end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants() local list={};for _,child in self.children do table.insert(list,child);for _,v in child:GetDescendants() do table.insert(list,v) end end;return list end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:SetAttribute(key,value) self.attributes[key]=value end
function methods:Clone()
 local copy=U.Node(self.Name,self.ClassName)
 for k,v in self.props do if k~='Parent' and k~='Destroying' and k~='DescendantAdded' and k~='Activated' and k~='MouseEnter' and k~='MouseLeave' then copy.props[k]=if type(v)=='table' then table.clone(v) else v end end
 for _,child in self.children do child:Clone().Parent=copy end
 return copy
end
function methods:Destroy()
 if self.destroyed then return end
 self.destroyed=true;self.Destroying:Fire()
 for _,c in self:GetChildren() do c:Destroy() end
 self.Parent=nil
end
U.workspace=U.Node('Workspace','Workspace')
U.cameraSignal=B.Signal();U.cameraChanged=B.Signal()
U.workspace.CurrentCamera={ViewportSize={X=1920,Y=1080},GetPropertyChangedSignal=function()return U.cameraSignal end}
function U.workspace:GetPropertyChangedSignal() return U.cameraChanged end
U.gui=U.Node('GameScreenGui','ScreenGui')
U.modal=U.Node('ModalButton','ImageButton');U.modal.Visible=false;U.modal.Parent=U.gui
U.canvas=U.Node('WindowCanvas','Frame');U.canvas.Parent=U.gui
U.scale=U.Node('UIScale','UIScale');U.scale.Scale=1;U.scale.Parent=U.canvas
U.templates=U.Node('UI','Folder')
U.template=U.Node('TestWindow','Frame');U.template.Parent=U.templates
local label=U.Node('Label','TextLabel');label.Parent=U.template
U.TweenService={Create=function()
 local tween={Completed=B.Signal()}
 function tween:Play() self.Completed:Fire(B.Enum.PlaybackState.Completed) end
 function tween:Cancel() end
 function tween:Destroy() end
 return tween
end}
U.ClientMsg={FireOpenWindow=function(id)table.insert(U.messages,'open:'..id)end,FireCloseWindow=function(id)table.insert(U.messages,'close:'..id)end}
U.TextFitting={FitTextLabel=function() return 22 end,FitTextWithShadow=function()return 22 end,FitMarkedText=function()return 22 end,FitMarkedRoot=function()end}
U.Sound={Play=function()U.sounds+=1 end}
U.Players={LocalPlayer=U.Node('LocalPlayer','Player')}
U.playerGui=U.Node('PlayerGui','PlayerGui');U.playerGui.Parent=U.Players.LocalPlayer
local root=U.Node('CenterFrame','Frame');root.Parent=U.gui
local scale=U.Node('UIScale','UIScale');scale.Parent=root
U.gui:Clone().Parent=U.templates
U.GameFrameWrapper={new=function()return {Init=function()end,OnDestroy=function()end}end}
return U
