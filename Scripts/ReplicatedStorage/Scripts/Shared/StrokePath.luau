-- 连续笔迹几何：同面跨帧连接、断笔隔离与共线线段合并，供客户端渲染调用
--!strict
local Types = require(script.Parent.GameTypes)
local Config = require(script.Parent.GameConfig)
local Path = {}
export type Tip = { sample: Types.Sample, from: Vector2, point: Vector2 }
export type Segment = { tip: Tip, reuse: boolean, skip: boolean }
function Path.Next(previous: Tip?, sample: Types.Sample, dimensions: Vector2): Segment
	local u = if sample.face <= 4 then 1 - sample.u else sample.u
	local point = Vector2.new(u * dimensions.X, sample.v * dimensions.Y)
	local from = point
	local connected = previous and not sample.breakBefore and previous.sample.part == sample.part and previous.sample.face == sample.face
	if connected and previous then from = previous.point end
	local delta = point - from
	local reuse = false
	local skip = connected ~= nil and connected ~= false and delta.Magnitude < Config.PaintVisualWidth * 0.02
	if connected and previous and not skip then
		local old = previous.point - previous.from
		local extended = point - previous.from
		if old.Magnitude < 0.001 then
			reuse = true
		elseif delta.Magnitude > 0.001 and extended.Magnitude > 0.001 then
			local deviation = math.abs(extended.X * old.Y - extended.Y * old.X) / extended.Magnitude
			reuse = old.Unit:Dot(delta.Unit) > 0.995 and deviation < Config.PaintVisualWidth * 0.15
		end
		if reuse then from = previous.from end
	end
	return {tip={sample=sample,from=from,point=point},reuse=reuse,skip=skip}
end
return Path
