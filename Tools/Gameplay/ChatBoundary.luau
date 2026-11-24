-- 聊天命令离线边界：捕获传送选项，不操作真实存档或传送服务
local B=require('./FoundationBoundary')
local C={Config=table.clone(require('./GameConfig')),calls={},options={},addedCoins={},studio=false,gm=true,fail=false,game={GameId=0}}
C.Config.ClearDataStorePlaceId=123
C.Config.GamePlaceId=456
C.command=B.Signal()
C.addCoinsCommand=B.Signal()
local commands={
 ClearDataStoreCommand={IsA=function(_,name)return name=='TextChatCommand'end,Triggered=C.command},
 AddCoinsCommand={IsA=function(_,name)return name=='TextChatCommand'end,Triggered=C.addCoinsCommand},
}
C.TextChatService={FindFirstChild=function(_,folderName)
 if folderName~='CustomTextChatCommands' then return nil end
 return {FindFirstChild=function(_,cmdName)return commands[cmdName]end}
end}
C.Players={GetPlayerByUserId=function(_,id)return if id==B.player.UserId then B.player else nil end}
C.RunService={IsStudio=function()return C.studio end}
C.GMConfig={IsGMPlayer=function()return C.gm end}
C.Info={AddCoins=function(player,amount)
 table.insert(C.addedCoins,{player=player,amount=amount})
 return true
end}
C.Instance={new=function(class)
 assert(class=='TeleportOptions','unexpected runtime instance')
 local options={}
 function options:SetTeleportData(value)self.data=value end
 function options:Destroy()self.destroyed=true end
 table.insert(C.options,options)
 return options
end}
C.TeleportService={TeleportAsync=function(_,place,players,options)
 table.insert(C.calls,{place=place,players=players,data=options.data})
 if C.fail then error('offline teleport failure') end
end}
C.player=B.player
return C
