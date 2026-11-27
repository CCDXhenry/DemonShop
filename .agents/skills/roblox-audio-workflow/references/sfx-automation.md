# Codex SFX 自动化

用于生成、校准、选择、上传和部署指定 SFX，也用于继续此前待审核的部署。BGM 走原有流程。项目目录、凭据名称和 Studio 入口以项目约定为准。

## 候选与试听

1. 在目标项目确定 Sound 名、触发位置、目标时长和用途。用户明确要生成新音效时，用 ElevenLabs 官方插件的 Flow 工具，每条默认生成一个候选。先查询可用节点和模型参数。需要指定时长时，配置 SFX 节点后以 `generations_count=1` 运行一次。等待时按原 Flow 和 session 查询状态。用户要求再出一版时才重新生成。
2. 下载同一 generation 已生成的文件。下载不额外扣积分。链接过期时查询同一 generation 的新链接，禁止为取文件重跑节点。若插件不可用，报告连接问题。用户要求更换素材来源时再用已有授权素材或本地合成。
3. 在项目的忽略目录保存原件（DemonShop 使用 `.cache/audio/<SoundName>/<generationId>/`）、Flow ID、generation ID、模型、提示词和素材来源。按触发时机裁切并处理首尾，在适用时选用 3D 单声道。保留原件、目标和实测时长、峰值、处理参数及源文件和成品的 SHA-256。给用户试听链接及候选信息。保留发布用途所需的授权依据，不将限时下载链接或凭据写入版本库。
4. 用户选定成品后，把选定的成品哈希、音效名称、目标 Place 和实际归属写入本次记录。若当前请求已经授权部署这些音效，选择后直接续跑。

## 上传、审核与续跑

1. 用独立候选目录暂存成品，复制正式清单为暂存清单，并保留正式条目的基线与旧音频。以相同文件名存放选定的成品，供既有上传工具校验。先核对选定哈希和实际 Creator，再用暂存路径调用项目上传工具，只处理已选名称。相同哈希沿用已有 ID。上传状态不明时查原操作或 Creator Dashboard，避免重新创建资产。
2. 上传拿到 ID 后，调用项目审核工具查询一次。分别记录每个名称的资产 ID、成品哈希、Place、归属及审核结果。审核通过的项目进入部署。待审核、拒绝或无法查询的项目保留暂存记录和正式映射，报告当前状态。
3. 用户说「继续部署」时，从候选记录和暂存清单定位同一 Place、名称、哈希和资产 ID。对尚未完成的音效查一次审核，沿用已有资产 ID。若存在多个待续跑的候选且目标不明确，先确认候选。没有选定记录时先请用户选择。

在 DemonShop 中，审核工具用法如下。调整路径、Place、归属和凭据环境变量以匹配已验证的目标。

```powershell
python Tools/Audio/check_roblox_audio_moderation.py --names AltarComplete --sounds-dir $stage --staged-manifest "$stage/manifest.staged.json" --status-file "$stage/review.json" --place-id 110812537538556 --creator-type group --creator-id 33977495 --api-key-env SIXCUBE_ROBLOX_OPENCLOUD_KEY
```

## Studio 部署与读回

1. 逐条核对暂存清单、选定哈希、审核记录和审批通过的 asset ID。用 Studio MCP 找到唯一匹配的 Edit 会话，明确指定会话 ID。读回 Place、Creator 和目标 Sound 的原 ID 及现有调音。目标冲突时暂停相应项目。
2. 用相同的暂存目录、暂存清单、归属和已通过的音效名称调用项目部署脚本生成 Luau。在 DemonShop 传入 `--place-id`，让生成的 Luau 在同一次调用内断言 PlaceId、Edit 模式和 Creator。更新指定模板后，另行只读核对 ID、调音、播放速度及循环属性。
3. 读回成功后，只合入本次确认部署的成品和清单条目，保留其上传历史。合入前重新核对同名正式条目的基线，保留其他条目。如果 Studio 已切换而本地合入中断，续跑时先读回并补齐本地记录。交付时分别报告生成、校准、审核、部署与读回的结果。听感与 Play 验证按实际发生情况报告。
