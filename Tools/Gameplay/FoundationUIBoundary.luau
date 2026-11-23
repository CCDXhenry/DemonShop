-- GUI 离线边界：只替换引擎节点、信号与 Tween，窗口管理器执行正式源码
local B=require('./FoundationBoundary')
local U={Enum=B.Enum,TweenInfo={new=function() return {} end},messages={},sounds=0}
local methods={}
local mt={}
function mt.__index(self,key)
 local value=self.props[key]
 if value~=nil then return value end
 return methods[key]
end
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
 return setmetatable({props={Name=name,ClassName=class,ZIndex=1,Visible=true,Active=true,attributes={},Destroying=B.Signal(),DescendantAdded=B.Signal(),AncestryChanged=B.Signal(),Activated=B.Signal(),MouseEnter=B.Signal(),MouseLeave=B.Signal(),InputBegan=B.Signal(),InputEnded=B.Signal()},children={},signals={}},mt)
end
function methods:IsA(class) return self.ClassName==class or (class=='GuiObject' and (self.ClassName=='Frame' or self.ClassName=='ImageButton' or self.ClassName=='ImageLabel' or self.ClassName=='TextLabel')) or (class=='GuiButton' and self.ClassName=='ImageButton') end
function methods:FindFirstChild(name,recursive)
 for _,c in self.children do if c.Name==name then return c end end
 if recursive then for _,c in self.children do local found=c:FindFirstChild(name,true);if found then return found end end end
end
function methods:IsDescendantOf(parent)
 local ancestor=self.Parent
 while ancestor do if ancestor==parent then return true end;ancestor=ancestor.Parent end
 return false
end
function methods:FindFirstAncestorWhichIsA(class)
 local ancestor=self.Parent
 while ancestor do if ancestor:IsA(class) then return ancestor end;ancestor=ancestor.Parent end
end
function methods:GetPropertyChangedSignal(key)
 if not self.signals[key] then self.signals[key]=B.Signal() end
 return self.signals[key]
end
function methods:ResetPropertyToDefault(key) self.props[key]=nil end
function methods:FindFirstChildOfClass(class) for _,c in self.children do if c.ClassName==class then return c end end end
function methods:WaitForChild(name) local child=self:FindFirstChild(name);assert(child,name);return child end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants() local list={};for _,child in self.children do table.insert(list,child);for _,v in child:GetDescendants() do table.insert(list,v) end end;return list end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:SetAttribute(key,value) self.attributes[key]=value end
function methods:Clone()
 local copy=U.Node(self.Name,self.ClassName)
 for k,v in self.props do if k~='Parent' and k~='Destroying' and k~='DescendantAdded' and k~='AncestryChanged' and k~='Activated' and k~='MouseEnter' and k~='MouseLeave' and k~='InputBegan' and k~='InputEnded' then copy.props[k]=if type(v)=='table' then table.clone(v) else v end end
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
local brush=U.Node('PaintBrushCursorImage','ImageLabel');brush.Visible=false;brush.Parent=root
local scale=U.Node('UIScale','UIScale');scale.Parent=root
for _,name in {'CoinsText','CarryText','StockText','HintText','NoticeText','ProgressText'} do
 local label=U.Node(name,'TextLabel');label.Parent=root
end
for _,name in {'ExitPaintButton','ResetViewButton'} do
 local button=U.Node(name,'ImageButton');button.Parent=root
 local label=U.Node('LabelText','TextLabel');label.Parent=button
end
local paint=U.Node('PaintFrame','Frame');paint.Parent=root
local fill=U.Node('FillFrame','Frame');fill.Parent=paint
local touchPaint=U.Node('TouchPaintFrame','Frame');touchPaint.Parent=U.gui
for _,buttonName in {'ExitPaintButton','ResetViewButton'} do
 local button=U.Node(buttonName,'ImageButton');button.Parent=touchPaint
 local label=U.Node('LabelText','TextLabel');label.Parent=button
end
local Roblox=require('@lune/roblox')
local attackFrame=U.Node('TouchAttackFrame','Frame')
attackFrame.Visible=false
attackFrame.Position=Roblox.UDim2.fromOffset(0,0)
attackFrame.AbsolutePosition=Roblox.Vector2.zero
attackFrame:SetAttribute('MinimumTouchSize',64)
attackFrame:SetAttribute('JumpGap',8)
attackFrame:SetAttribute('JumpSizeRatio',0.9)
attackFrame.Parent=U.templates
local attackButton=U.Node('AttackButton','ImageButton');attackButton.Parent=attackFrame
local throwStick=U.Node('ThrowStick','Frame')
throwStick.Visible=false
throwStick.Position=Roblox.UDim2.fromOffset(0,0)
throwStick.AbsolutePosition=Roblox.Vector2.zero
throwStick.Parent=U.templates
local stickButton=U.Node('StickButton','ImageButton');stickButton.Parent=throwStick
local knob=U.Node('KnobImage','ImageLabel');knob.Parent=stickButton
attackButton:SetAttribute('PressedScale',0.86)
attackButton:SetAttribute('PressTweenSeconds',0.1)
local attackScale=U.Node('UIScale','UIScale');attackScale.Scale=1;attackScale.Parent=attackButton
local actionText=U.Node('ActionText','TextLabel');actionText.Parent=attackButton
U.gui:Clone().Parent=U.templates
local target=U.Node('TargetGui','BillboardGui');target.Parent=U.templates
local fill=U.Node('FillImage','ImageLabel');fill.Parent=target
local guide=U.Node('ScreenLayoutGuideFrame','Frame');guide.Parent=U.templates
U.UserInputService={TouchEnabled=false,MouseIconEnabled=true,PreferredInput=U.Enum.PreferredInput.KeyboardAndMouse,GetPropertyChangedSignal=function() return B.Signal() end,GetMouseLocation=function() return Roblox.Vector2.zero end}
U.GuiService={MenuIsOpen=false}
U.TranslationTool={
 CustomAutoLocalizeTextLabel=function(label,source,key,args) label.Text=source;label.translationKey=key;label.translationArgs=args end,
 RemoveCustomAutoLocalizeGui=function(label) label.translationKey=nil end,
}
U.PaintPointer={HideLegacyCursor=function(root) U.pointerRoot=root end,PlaceBrush=function() end}
U.GameFrameWrapper={new=function()return {Init=function()end,OnDestroy=function()end}end}
return U
