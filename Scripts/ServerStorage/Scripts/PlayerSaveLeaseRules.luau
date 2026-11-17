-- 玩家存档会话纯规则：以租约、存储修订号和操作标识拒绝旧会话、乱序写入与重复重试
--!strict
export type Metadata = { [string]: unknown }
type Lease = { owner: string?, expiresAt: number, revision: number, operationId: string? }
-- 历史持久化键：保留原始字符串以兼容现有租约、修订号与重复写入保护。
local MetadataKeys = table.freeze({
	SessionId = "DemoSessionId",
	SessionExpires = "DemoSessionExpires",
	SaveRevision = "DemoSaveRevision",
	SaveOperation = "DemoSaveOperation",
})
local Rules = { MetadataKeys = MetadataKeys }
local function Read(metadata: Metadata): Lease?
	local owner, expires, revision, operation = metadata[MetadataKeys.SessionId], metadata[MetadataKeys.SessionExpires], metadata[MetadataKeys.SaveRevision], metadata[MetadataKeys.SaveOperation]
	if revision == nil then
		revision = 0
	end
	if type(revision) ~= "number" or revision ~= revision or revision < 0 or revision % 1 ~= 0 or revision >= 9007199254740991 then
		return nil
	end
	if owner ~= nil and (type(owner) ~= "string" or #owner == 0) then
		return nil
	end
	if owner ~= nil and (type(expires) ~= "number" or expires ~= expires or math.abs(expires) == math.huge) then
		return nil
	end
	if owner == nil and expires ~= nil then
		return nil
	end
	if operation ~= nil and type(operation) ~= "string" then
		return nil
	end
	local lease: Lease =
		{ owner = owner :: string?, expiresAt = if type(expires) == "number" then expires else 0, revision = revision, operationId = operation :: string? }
	return lease
end
function Rules.Acquire(metadata: Metadata, token: string, now: number, duration: number): (Metadata?, string?)
	local lease = Read(metadata)
	if not lease then
		return nil, "invalidMetadata"
	end
	if lease.owner and lease.owner ~= token and lease.expiresAt > now then
		return nil, "sessionBusy"
	end
	local result = table.clone(metadata)
	result[MetadataKeys.SessionId], result[MetadataKeys.SessionExpires] = token, now + duration
	result[MetadataKeys.SaveRevision], result[MetadataKeys.SaveOperation] = lease.revision, nil
	return result, nil
end
function Rules.Write(
	metadata: Metadata,
	token: string,
	now: number,
	duration: number,
	expectedRevision: number,
	operationId: string
): (Metadata?, boolean, string?)
	local lease = Read(metadata)
	if not lease then
		return nil, false, "invalidMetadata"
	end
	if lease.owner ~= token or lease.expiresAt <= now then
		return nil, false, "leaseLost"
	end
	local replay = lease.revision == expectedRevision + 1 and lease.operationId == operationId
	if not replay and lease.revision ~= expectedRevision then
		return nil, false, "staleRevision"
	end
	local result = table.clone(metadata)
	result[MetadataKeys.SessionExpires] = now + duration
	result[MetadataKeys.SaveRevision] = if replay then lease.revision else lease.revision + 1
	result[MetadataKeys.SaveOperation] = operationId
	return result, replay, nil
end
function Rules.Release(metadata: Metadata, token: string): Metadata?
	local lease = Read(metadata)
	if not lease or lease.owner ~= token then
		return nil
	end
	local result = table.clone(metadata)
	result[MetadataKeys.SessionId], result[MetadataKeys.SessionExpires], result[MetadataKeys.SaveOperation] = nil, nil, nil
	return result
end
function Rules.GetRevision(metadata: Metadata): number?
	local lease = Read(metadata)
	return if lease then lease.revision else nil
end
return Rules
