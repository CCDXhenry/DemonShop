local B={count=0,workspace={GetServerTimeNow=function() return 100 end}}
B.Net={Broadcast=function() B.count+=1 end}
return B
