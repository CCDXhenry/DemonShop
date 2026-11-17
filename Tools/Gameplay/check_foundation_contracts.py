"""Guard the read-only reference's public module contracts and project boundaries."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
manifest=json.loads((ROOT/'Tools/Gameplay/foundation-reference.json').read_text(encoding='utf-8'))
checks=0

def check(value,label):
 global checks
 assert value,label
 checks+=1

def local_script(path):
 base=ROOT/'Scripts'/Path(*path.split('.'))
 for candidate in (base.with_suffix('.luau'),base/'init.luau',base.with_suffix('.legacy.luau'),base.with_suffix('.local.luau')):
  if candidate.is_file():return candidate
 return None

def count_parameters(value):
 depth=0;count=1 if value.strip() else 0
 for c in value:
  if c in '({[':depth+=1
  elif c in ')}]':depth-=1
  elif c==',' and depth==0:count+=1
 return count

def signature(source,method):
 match=re.search(r'function\s+\w+\.'+re.escape(method)+r'\s*\(',source)
 if not match:return None
 depth=1;index=match.end()
 for end in range(index,len(source)):
  if source[end]=='(':depth+=1
  elif source[end]==')':
   depth-=1
   if not depth:return source[index:end]
 raise AssertionError('Unclosed function '+method)

for row in manifest['rows']:
 if row['class'] not in ('ModuleScript','LocalScript','Script'):continue
 file=local_script(row['path'])
 check(file is not None,'Missing reference module '+row['path'])
 source=file.read_text(encoding='utf-8')
 check(len(source.strip())>40,'Empty reference module '+row['path'])
 for contract in row.get('contracts',[]):
  method=contract['method'];actual=signature(source,method)
  check(actual is not None or re.search(r'\w+\.'+re.escape(method)+r'\s*=',source),'Missing public method '+row['path']+'.'+method)
  if actual is not None:
   check(count_parameters(actual)>=count_parameters(contract['parameters']),'Removed public parameters '+row['path']+'.'+method)
for path,name in [('ServerStorage.Scripts.ServerGameManager','ServerGameManager'),('ReplicatedStorage.Scripts.Client.ClientGameManager','ClientGameManager'),('ServerStorage.Scripts.ServerGameManager.ServerMarketplaceManager','ServerMarketplaceManager'),('ServerStorage.Scripts.ServerGameManager.ServerPlayerSettingManager','ServerPlayerSettingManager'),('ServerStorage.Scripts.ServerGameManager.ServerPlayerChatCommandManager','ServerPlayerChatCommandManager')]:
 check('export type '+name+' =' in local_script(path).read_text(encoding='utf-8'),'reference exported type '+name)
shared=ROOT/'Scripts/ReplicatedStorage/Scripts/Shared'
net=(shared/'NetMsg.luau').read_text(encoding='utf-8')
installer=(ROOT/'Tools/Gameplay/build-foundation-assets.luau').read_text(encoding='utf-8')
for row in manifest['rows']:
 if row['class']=='RemoteEvent':
  name=row['path'].split('.')[-1]
  check('"'+name+'"' in installer and '"'+name+'"' in net,'Missing reference event '+name)
config=(shared/'GameConfig.luau').read_text(encoding='utf-8')
check('local GameConfig = {}' in config and 'return GameConfig' in config,'reference configuration module shape')
sections=['GameConfig.GameVersion =','GameConfig.ABTestVersion =','GameConfig.PlayerSaveInfoDataVersion =','GameConfig.GameId =','GameConfig.GamePassId =','GameConfig.GamePassPrice =','export type SettingInfo =','export type PlayerConfigInfo =','export type PlayerSaveInfo =','export type PlayerInfo = PlayerSaveInfo &','export type ReceiptInfo =','function GameConfig.CreateDefaultPlayerSaveInfo(','export type ClientLocalPlayerSaveInfo =','export type ClientOtherPlayerSaveInfo =']
check(all(section in config for section in sections) and [config.index(section) for section in sections]==sorted(config.index(section) for section in sections),'reference configuration section order')
check('PersistentPlayerSaveInfo' not in config and 'AsPlayerSaveInfo' not in config and 'setmetatable' not in config,'storage adapters stay outside base configuration')
processing=(ROOT/'Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau').read_text(encoding='utf-8')
check('WaitForChild("GameScreenGui")' not in processing and 'Own(gui)' not in processing,'Processing must not own global GUI')
for path in ('Scripts/ServerStorage/Scripts/ProcessingManager.luau','Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau'):
 source=(ROOT/path).read_text(encoding='utf-8')
 check('DataStoreService' not in source and 'Players.PlayerAdded' not in source and 'Players.PlayerRemoving' not in source,'Processing must not own player persistence/lifecycle')
check('FoundationNotify' not in (shared/'FoundationNet.luau').read_text(encoding='utf-8'),'Retired foundation transport accessed')
server=ROOT/'Scripts/ServerStorage/Scripts'
info=(server/'ServerGameInfo.luau').read_text(encoding='utf-8')
check('setmetatable' not in info and 'export type PlayerInfo = Config.PlayerInfo' in info,'public native PlayerInfo has no proxy metatable')
check('local sessions:' in info and 'profile:' not in info and 'record.profile' not in info,'save session bookkeeping is private and not a second profile')
check('function Info.AcquirePlayerSaveInfo(' in info and 'function Info.Load(' not in info,'acquisition is separate from native initialization')
init=info[info.index('function Info.InitPlayerInfo('):info.index('function Info.CreatePlayerSaveInfoByPlayerInfo(')]
check('ServerMsg.FirePlayerInfoInit(player)' in init and 'Info.SendPlayerInfo(player)' in init and 'Net.FireNotifyPlayersOtherPlayerInfoInit' in init,'native initialization owns all foundation notifications')
manager=(server/'ServerGameManager/init.luau').read_text(encoding='utf-8')
add=manager[manager.index('function Manager.AddPlayer('):manager.index('function Manager.SavePlayer(')]
check(add.index('AcquirePlayerSaveInfo')<add.index('Context.ResolveConfig')<add.index('Info.InitPlayerInfo')<add.index('self.processing:AddPlayer'),'final player configuration precedes published initialization and gameplay')
check('Info.SendPlayerInfo' not in add,'root does not duplicate initial native notice')
store=(server/'ServerPlayerSaveStore.luau').read_text(encoding='utf-8')
check('SaveRules.Migrate(current)' in store and 'VersionUpdate' not in store,'storage migration stays at version boundary')
migration=(server/'PlayerSaveInfoVersionUpdateTool/init.luau').read_text(encoding='utf-8')
check('PlayerSaveInfoVersionUpdate1' in migration and 'PlayerSaveInfoVersionUpdate2' in migration and 'Rules.Migrate(value)' not in migration,'native migrations retain ordered version steps')
client=(ROOT/'Scripts/ReplicatedStorage/Scripts/Client/ClientGameManager.luau').read_text(encoding='utf-8')
check('StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)' in client,'foundation disables native backpack')
chat=(server/'ServerGameManager/ServerPlayerChatCommandManager.luau').read_text(encoding='utf-8')
check('defaultPlayerSaveInfo = Config.CreateDefaultPlayerSaveInfo()' in chat and 'gameStartPlaceId = Config.GamePlaceId' in chat,'reset teleport uses native save and configured entry')
analytics=(server/'AnalyticsTool.luau').read_text(encoding='utf-8')
check('function Analytics.Flush(' in analytics and 'function Analytics.Close(' in analytics and 'Analytics.Close(deadline)' in manager,'analytics has owner-coordinated flush and deadline')
server_config=(server/'ServerConfig.luau').read_text(encoding='utf-8')
check('local ServerConfig = {}' in server_config and 'return ServerConfig' in server_config and 'table.freeze' not in server_config,'reference server config module shape')
print(f'PASS: {checks} read-only reference module/API and boundary contracts')
