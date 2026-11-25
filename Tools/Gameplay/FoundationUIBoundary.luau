-- GUI 离线边界：只替换引擎节点、信号与 Tween，窗口管理器执行正式源码
local B=require('./FoundationBoundary')
local U={Enum=B.Enum,TweenInfo={new=function(seconds,style,direction) return {Time=seconds,EasingStyle=style,EasingDirection=direction} end},messages={},sounds=0}
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
 return setmetatable({props={Name=name,ClassName=class,ZIndex=1,Visible=true,Enabled=true,Active=true,Interactable=true,attributes={},Destroying=B.Signal(),DescendantAdded=B.Signal(),AncestryChanged=B.Signal(),Activated=B.Signal(),MouseEnter=B.Signal(),MouseLeave=B.Signal(),InputBegan=B.Signal(),InputEnded=B.Signal(),CharacterAdded=B.Signal(),CharacterRemoving=B.Signal()},children={},signals={},attrSignals={}},mt)
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
function methods:FindFirstAncestor(name)
 local ancestor=self.Parent
 while ancestor do if ancestor.Name==name then return ancestor end;ancestor=ancestor.Parent end
 return nil
end
function methods:FindFirstAncestorWhichIsA(class)
 local ancestor=self.Parent
 while ancestor do if ancestor:IsA(class) then return ancestor end;ancestor=ancestor.Parent end
end
function methods:GetPropertyChangedSignal(key)
 if not self.signals[key] then self.signals[key]=B.Signal() end
 return self.signals[key]
end
function methods:GetAttributeChangedSignal(key)
 if not self.attrSignals[key] then self.attrSignals[key]=B.Signal() end
 return self.attrSignals[key]
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
 for k,v in self.props do if k~='Parent' and k~='Destroying' and k~='DescendantAdded' and k~='AncestryChanged' and k~='Activated' and k~='MouseEnter' and k~='MouseLeave' and k~='InputBegan' and k~='InputEnded' and k~='CharacterAdded' and k~='CharacterRemoving' then copy.props[k]=if type(v)=='table' then table.clone(v) else v end end
 for k,v in self.attributes do copy.attributes[k]=v end
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
U.gui=U.Node('GameScreenGui','ScreenGui');U.gui.IgnoreGuiInset=true;U.gui.ScreenInsets=B.Enum.ScreenInsets.None
U.modal=U.Node('ModalButton','ImageButton');U.modal.Visible=false;U.modal.Parent=U.gui
U.canvas=U.Node('WindowCanvas','Frame');U.canvas.Parent=U.gui
U.scale=U.Node('UIScale','UIScale');U.scale.Scale=1;U.scale.Parent=U.canvas
U.templates=U.Node('UI','Folder')
U.template=U.Node('TestWindow','Frame');U.template.Parent=U.templates
local label=U.Node('Label','TextLabel');label.Parent=U.template
U.manualTweens={}
U.TweenService={Create=function(_service,target,info,properties)
 local tween={Completed=B.Signal(),PlaybackState=B.Enum.PlaybackState.Begin,Info=info,Goals=properties}
 function tween:Finish()
  if self.PlaybackState~=B.Enum.PlaybackState.Playing then return end
  for key,value in properties do target[key]=value end
  self.PlaybackState=B.Enum.PlaybackState.Completed
  self.Completed:Fire(self.PlaybackState)
 end
 function tween:Play()
  self.StartScale=target.Scale
  self.PlaybackState=B.Enum.PlaybackState.Playing
  if U.manualTweens[target] then
   U.manualTweens[target]=self
  else
   self:Finish()
  end
 end
 function tween:Cancel()
  if self.PlaybackState~=B.Enum.PlaybackState.Playing then return end
  self.PlaybackState=B.Enum.PlaybackState.Cancelled
  self.Completed:Fire(self.PlaybackState)
 end
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
 local node=U.Node(name,'TextLabel');node.Parent=root
end
for _,name in {'ExitPaintButton','ResetViewButton'} do
 local button=U.Node(name,'ImageButton');button.Visible=false;button.Parent=root
 local btnLabel=U.Node('LabelText','TextLabel');btnLabel.Parent=button
end
local paint=U.Node('PaintFrame','Frame');paint.Visible=false;paint.Parent=root
local fill=U.Node('FillFrame','Frame');fill.Parent=paint
local Roblox=require('@lune/roblox')
local touchControls=U.Node('TouchControlsFrame','Frame')
touchControls.Size=Roblox.UDim2.fromOffset(1920,1080)
touchControls.AnchorPoint=Roblox.Vector2.new(0.5,0.5)
touchControls.Position=Roblox.UDim2.fromScale(0.5,0.5)
touchControls.Visible=false
touchControls.Parent=root

local function addSlot(name, cx, cy, sizePx, visible)
 local slot=U.Node(name,'Frame')
 slot.AnchorPoint=Roblox.Vector2.new(0.5,0.5)
 slot.Position=Roblox.UDim2.fromOffset(cx,cy)
 slot.Size=Roblox.UDim2.fromOffset(sizePx,sizePx)
 slot.Visible=visible
 slot.Parent=touchControls
 return slot
end
local function addAction(slot, btnName, textValue, designSize)
 local btn=U.Node(btnName,'ImageButton')
 btn.AnchorPoint=Roblox.Vector2.new(0.5,0.5)
 btn.Position=Roblox.UDim2.fromScale(0.5,0.5)
 btn.Size=Roblox.UDim2.fromScale(1,1)
 btn:SetAttribute('HasInteractionEffect',true)
 btn:SetAttribute('HasClickSound',false)
 btn:SetAttribute('ScaleWhilePressed',true)
 btn:SetAttribute('PressedScale',0.86)
 btn:SetAttribute('PressTweenSeconds',0.1)
 btn.Parent=slot
 local btnScale=U.Node('UIScale','UIScale');btnScale.Scale=1;btnScale.Parent=btn
 local actionText=U.Node('ActionText','TextLabel');actionText.Text=textValue;actionText:SetAttribute('DesignTextSize',designSize);actionText.Parent=btn
 return btn
end

local jumpFrame=addSlot('TouchJumpFrame',1765,915,190,true)
addAction(jumpFrame,'JumpButton','JUMP',26)
local attackFrame=addSlot('TouchAttackFrame',1545,845,190,true)
addAction(attackFrame,'AttackButton','ATTACK',26)
local throwStick=addSlot('ThrowStick',1545,845,190,false)
local stickButton=U.Node('StickButton','ImageButton');stickButton:SetAttribute('HasInteractionEffect',true);stickButton:SetAttribute('HasClickSound',false);stickButton.Parent=throwStick
local stickScale=U.Node('UIScale','UIScale');stickScale.Scale=1;stickScale.Parent=stickButton
local knob=U.Node('KnobImage','ImageLabel');knob.Parent=stickButton
local sprintFrame=addSlot('TouchSprintFrame',1765,695,156,true)
addAction(sprintFrame,'SprintButton','SPRINT',24)

U.gui:Clone().Parent=U.templates
local target=U.Node('TargetGui','BillboardGui');target.Parent=U.templates
local targetFill=U.Node('FillImage','ImageLabel');targetFill.Parent=target
local guide=U.Node('ScreenLayoutGuideFrame','Frame');guide.Parent=U.templates
local preferredInputSignal=B.Signal()
U.RunService={RenderStepped=B.Signal()}
U.UserInputService={InputBegan=B.Signal(),InputEnded=B.Signal(),WindowFocusReleased=B.Signal(),PreferredInputChanged=preferredInputSignal,TouchEnabled=false,MouseIconEnabled=true,PreferredInput=U.Enum.PreferredInput.KeyboardAndMouse,GetPropertyChangedSignal=function(_self,key) if key=='PreferredInput' then return preferredInputSignal end return B.Signal() end,GetMouseLocation=function() return Roblox.Vector2.zero end}
U.GuiService={MenuIsOpen=false,MenuOpened=B.Signal(),GetGuiInset=function() return Roblox.Vector2.new(0,36) end}
U.TranslationTool={
 CustomAutoLocalizeTextLabel=function(lbl,source,key,args) lbl.Text=source;lbl.translationKey=key;lbl.translationArgs=args end,
 RemoveCustomAutoLocalizeGui=function(lbl) lbl.translationKey=nil end,
}
U.PaintPointer={HideLegacyCursor=function(r) U.pointerRoot=r end,PlaceBrush=function() end}
U.GameFrameWrapper={new=function()return {Init=function()end,OnDestroy=function()end}end}
return U
