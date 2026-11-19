local R=require('@lune/roblox')
local B={now=100}
B.workspace={GetServerTimeNow=function() return B.now end}
B.Scene={SigilPosition=R.Vector3.zero}
for _,name in {'PoolPickup','TableInteract','Altar','Shelf'} do B.Scene[name]={Position=R.Vector3.zero} end
B.Net={FireNotify=function()end}
B.Carry={Take=function(item,player) item.holder=player;item.location='Carried';return true end}
return B
