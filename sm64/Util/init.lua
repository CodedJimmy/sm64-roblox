--!strict

local Util = {
	GlobalTimer = 0,
	Scale = 1 / 16,
}

local rayParams = RaycastParams.new()
rayParams.CollisionGroup = "Player"

local SHORT_TO_RAD = (2 * math.pi) / 0x10000
local VECTOR3_XZ = Vector3.one - Vector3.yAxis

local CARDINAL = {
	-Vector3.xAxis,
	-Vector3.zAxis,
	Vector3.xAxis,
	Vector3.zAxis,
}

function Util.SetX(vec: Vector3, x: number): Vector3
	return Vector3.new(x, vec.Y, vec.Z)
end

function Util.SetXint16(vec: Vector3int16, x: number): Vector3int16
	return Vector3int16.new(x, vec.Y, vec.Z)
end

function Util.SetY(vec: Vector3, y: number): Vector3
	return Vector3.new(vec.X, y, vec.Z)
end

function Util.SetYint16(vec: Vector3int16, y: number): Vector3int16
	return Vector3int16.new(vec.X, y, vec.Z)
end

function Util.SetZ(vec: Vector3, z: number): Vector3
	return Vector3.new(vec.X, vec.Y, z)
end

function Util.SetZint16(vec: Vector3int16, z: number): Vector3int16
	return Vector3int16.new(vec.X, vec.Y, z)
end

function Util.ToRoblox(v: Vector3)
	return v * Util.Scale
end

function Util.ToSM64(v: Vector3)
	return v / Util.Scale
end

function Util.ToEulerAngles(v: Vector3int16): Vector3
	return Vector3.new(v.X, v.Y, v.Z) * SHORT_TO_RAD
end

function Util.ToRotation(v: Vector3int16): CFrame
	local angle = Util.ToEulerAngles(v)

	local matrix = CFrame.fromAxisAngle(Vector3.yAxis, angle.Y)
		* CFrame.fromAxisAngle(Vector3.xAxis, -angle.X)
		* CFrame.fromAxisAngle(Vector3.zAxis, -angle.Z)

	return matrix
end

function Util.Raycast(pos: Vector3, dir: Vector3, rayParams: RaycastParams?, worldRoot: WorldRoot?): RaycastResult?
	local root = worldRoot or workspace
	local result: RaycastResult? = root:Raycast(pos, dir)

	if script:GetAttribute("Debug") then
		local color = Color3.new(result and 0 or 1, result and 1 or 0, 0)

		local line = Instance.new("LineHandleAdornment")
		line.CFrame = CFrame.new(pos, pos + dir)
		line.Length = dir.Magnitude
		line.Thickness = 3
		line.Color3 = color
		line.Adornee = workspace.Terrain
		line.Parent = workspace.Terrain

		task.delay(2, line.Destroy, line)
	end

	return result
end

function Util.RaycastSM64(pos: Vector3, dir: Vector3, rayParams: RaycastParams?, worldRoot: WorldRoot?): RaycastResult?
	local result: RaycastResult? = Util.Raycast(pos * Util.Scale, dir * Util.Scale, rayParams, worldRoot)

	if result then
		-- Cast back to SM64 unit scale.
		result = {
			Normal = result.Normal,
			Material = result.Material,
			Instance = result.Instance,
			Distance = result.Distance / Util.Scale,
			Position = result.Position / Util.Scale,
		} :: any
	end

	return result
end

function Util.FindFloor(pos: Vector3): (number, RaycastResult?)
	local trunc = Vector3int16.new(pos.X, pos.Y, pos.Z)
	local height = -11000

	if math.abs(trunc.X) >= 0x2000 then
		return height, nil
	end

	if math.abs(trunc.Z) >= 0x2000 then
		return height, nil
	end

	local newPos = Vector3.new(trunc.X, trunc.Y, trunc.Z)
	local result = Util.RaycastSM64(newPos + (Vector3.yAxis * 100), -Vector3.yAxis * 10000)

	if result then
		local height = Util.SignedShort(result.Position.Y)
		result.Position = Vector3.new(pos.X, height, pos.Z)

		return height, result
	else
		return height, nil
	end
end

function Util.FindCeil(pos: Vector3, height: number?): (number, RaycastResult?)
	local pos = Vector3.new(pos.X, (height or pos.Y) + 80, pos.Z)
	local result = Util.RaycastSM64(pos, Vector3.yAxis * 10000)

	if result then
		return result.Position.Y, result
	else
		return 10000, nil
	end
end

function Util.FindWallCollisions(pos: Vector3, offset: number, radius: number): (Vector3, RaycastResult?)
	local origin = pos + Vector3.new(0, offset, 0)
	local walls: { RaycastResult } = {}
	local lastWall: RaycastResult?
	local disp = Vector3.zero

	for i, dir in CARDINAL do
		local contact = Util.RaycastSM64(origin, dir * radius)

		if contact then
			local normal = contact.Normal

			if math.abs(normal.Y) < 0.01 then
				local surface = contact.Position
				local offset = (surface - pos) * VECTOR3_XZ
				local dist = offset.Magnitude

				if dist < radius then
					disp += (contact.Normal * VECTOR3_XZ) * (radius - dist)
					lastWall = contact
				end
			end
		end
	end

	return pos + disp, lastWall
end

function Util.SignedShort(x: number)
	return -0x8000 + math.floor((x + 0x8000) % 0x10000)
end

function Util.SignedInt(x: number)
	return -0x80000000 + math.floor(x + 0x80000000) % 0x100000000
end

function Util.ApproachFloat(current: number, target: number, inc: number, dec: number?): number
	if dec == nil then
		dec = inc
	end

	assert(dec)

	if current < target then
		current = math.min(target, current + inc)
	else
		current = math.max(target, current - dec)
	end

	return current
end

function Util.ApproachInt(current: number, target: number, inc: number, dec: number?): number
	if dec == nil then
		dec = inc
	end

	assert(dec)

	if current < target then
		current = Util.SignedInt(current + inc)
		current = math.min(target, current)
	else
		current = Util.SignedInt(current - dec)
		current = math.max(target, current)
	end

	return Util.SignedInt(current)
end

function Util.Sins(short: number): number
	short = Util.SignedShort(short)
	return math.sin(short * SHORT_TO_RAD)
end

function Util.Coss(short: number): number
	short = Util.SignedShort(short)
	return math.cos(short * SHORT_TO_RAD)
end

local function atan2_lookup(y: number, x: number)
	return math.atan2(y, x) / SHORT_TO_RAD
end

function Util.Atan2s(y: number, x: number): number
	local ret: number

	if x >= 0 then
		if y >= 0 then
			if y >= x then
				ret = atan2_lookup(x, y)
			else
				ret = 0x4000 - atan2_lookup(y, x)
			end
		else
			y = -y

			if y < x then
				ret = 0x4000 + atan2_lookup(y, x)
			else
				ret = 0x8000 - atan2_lookup(x, y)
			end
		end
	else
		x = -x

		if y < 0 then
			y = -y

			if y >= x then
				ret = 0x8000 + atan2_lookup(x, y)
			else
				ret = 0xC000 - atan2_lookup(y, x)
			end
		else
			if y < x then
				ret = 0xC000 + atan2_lookup(y, x)
			else
				ret = -atan2_lookup(x, y)
			end
		end
	end

	return Util.SignedShort(ret)
end

return table.freeze(Util)
