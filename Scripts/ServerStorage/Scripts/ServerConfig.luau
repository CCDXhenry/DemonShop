-- 服务端基础配置：保留分段赋值结构，外部统计密钥默认未配置
--!strict
local ServerConfig = {}
-- 本项目 GameAnalytics 游戏密钥，空字符串不启用。
ServerConfig.GoogleAnalyticsGameKey = ""
-- 本项目 GameAnalytics 服务端密钥，空字符串不启用。
ServerConfig.GoogleAnalyticsSecretKey = ""
return ServerConfig
