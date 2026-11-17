-- 日期测试边界：保留默认存档工厂逻辑，替换引擎 UTC 日期服务
local D={DateTime={},DateTimeExtension={}}
local days={}
function D.DateTime.fromUnixTimestamp(timestamp)return {UnixTimestamp=timestamp} end
function D.DateTimeExtension.GetDate(value)
 local date=os.date('!*t',value.UnixTimestamp)
 days[date.year..':'..date.month..':'..date.day]=math.floor(value.UnixTimestamp/86400)*86400
 return {Year=date.year,Month=date.month,Day=date.day,Hour=0,Minute=0,Second=0,Millisecond=0}
end
function D.DateTime.fromUniversalTime(year,month,day)
 return {UnixTimestamp=assert(days[year..':'..month..':'..day],'date boundary must derive requested UTC date')}
end
return D
