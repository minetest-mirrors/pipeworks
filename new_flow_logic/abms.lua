-- reimplementation of new_flow_logic branch: processing functions
-- written 2017 by thetaepsilon



local flowlogic = {}
flowlogic.helpers = {}
pipeworks.flowlogic = flowlogic



-- borrowed from above: might be useable to replace the above coords tables
local make_coords_offsets = function(pos, include_base)
	local coords = {
		{x=pos.x,y=pos.y-1,z=pos.z},
		{x=pos.x,y=pos.y+1,z=pos.z},
		{x=pos.x-1,y=pos.y,z=pos.z},
		{x=pos.x+1,y=pos.y,z=pos.z},
		{x=pos.x,y=pos.y,z=pos.z-1},
		{x=pos.x,y=pos.y,z=pos.z+1},
	}
	if include_base then table.insert(coords, pos) end
	return coords
end



-- local debuglog = function(msg) print("## "..msg) end



--local formatvec = function(vec) local sep="," return "("..tostring(vec.x)..sep..tostring(vec.y)..sep..tostring(vec.z)..")" end

-- new version of liquid check
-- accepts a limit parameter to only delete water blocks that the receptacle can accept,
-- and returns it so that the receptacle can update it's pressure values.
local check_for_liquids_v2 = function(pos, limit)
	local coords = make_coords_offsets(pos, false)
	local total = 0
	for index, tpos in ipairs(coords) do
		if total >= limit then break end
		local name = minetest.get_node(tpos).name
		if name == "default:water_source" then
			minetest.remove_node(tpos)
			total = total + 1
		end
	end
	--pipeworks.logger("check_for_liquids_v2@"..formatvec(pos).." total "..total)
	return total
end
flowlogic.check_for_liquids_v2 = check_for_liquids_v2



local label_pressure = "pipeworks.water_pressure"
flowlogic.balance_pressure = function(pos, node)
	-- debuglog("balance_pressure() "..node.name.." at "..pos.x.." "..pos.y.." "..pos.z)
	-- check the pressure of all nearby nodes, and average it out.
	-- for the moment, only balance neighbour nodes if it already has a pressure value.
	-- XXX: maybe this could be used to add fluid behaviour to other mod's nodes too?

	-- unconditionally include self in nodes to average over
	local meta = minetest.get_meta(pos)
	local currentpressure = meta:get_float(label_pressure)
	local connections = { meta }
	local totalv = currentpressure
	local totalc = 1

	-- then handle neighbours, but if not a pressure node don't consider them at all
	for _, npos in ipairs(make_coords_offsets(pos, false)) do
		local nodename = minetest.get_node(npos).name
		local neighbour = minetest.get_meta(npos)
		-- for now, just check if it's in the simple table.
		-- TODO: the "can flow from" logic in flowable_node_registry.lua
		local haspressure = (pipeworks.flowables.list.simple[nodename])
		if haspressure then
			--pipeworks.logger("balance_pressure @ "..formatvec(pos).." "..nodename.." "..formatvec(npos).." added to neighbour set")
			local n = neighbour:get_float(label_pressure)
			table.insert(connections, neighbour)
			totalv = totalv + n
			totalc = totalc + 1
		end
	end

	local average = totalv / totalc
	for _, targetmeta in ipairs(connections) do
		targetmeta:set_float(label_pressure, average)
	end
end



flowlogic.run_input = function(pos, node, maxpressure, intakefn)
	-- intakefn allows a given input node to define it's own intake logic.
	-- this function will calculate the maximum amount of water that can be taken in;
	-- the intakefn will be given this and is expected to return the actual absorption amount.

	local meta = minetest.get_meta(pos)
	local currentpressure = meta:get_float(label_pressure)
	local intake_limit = maxpressure - currentpressure
	if intake_limit <= 0 then return end

	local actual_intake = intakefn(pos, intake_limit)
	--pipeworks.logger("run_input@"..formatvec(pos).." oldpressure "..currentpressure.." intake_limit "..intake_limit.." actual_intake "..actual_intake)
	if actual_intake <= 0 then return end

	local newpressure = actual_intake + currentpressure
	-- debuglog("oldpressure "..currentpressure.." intake_limit "..intake_limit.." actual_intake "..actual_intake.." newpressure "..newpressure)
	meta:set_float(label_pressure, newpressure)
end



-- flowlogic output helper implementation:
-- outputs water by trying to place water nodes nearby in the world.
-- neighbours is a list of node offsets to try placing water in.
-- this is a constructor function, returning another function which satisfies the output helper requirements.
flowlogic.helpers.make_neighbour_output = function(neighbours)
	return function(pos, node, currentpressure)
		local taken = 0
		for _, offset in pairs(neighbours) do
			local npos = vector.add(pos, offset)
			local name = minetest.get_node(npos).name
			if (name == "air") or (name == "default:water_flowing") then
				minetest.swap_node(npos, {name="default:water_source"})
				taken = taken + 1
			end
		end
		return taken
	end
end



flowlogic.run_output = function(pos, node, threshold, outputfn)
	-- callback for output devices.
	-- takes care of checking a minimum pressure value and updating the node metadata.
	-- the outputfn is provided the current pressure and returns the pressure "taken".
	-- as an example, using this with the above spigot function,
	-- the spigot function tries to output a water source if it will fit in the world.
	local meta = minetest.get_meta(pos)
	-- sometimes I wonder if meta:get_* returning default values would ever be problematic.
	-- though here it doesn't matter, an uninit'd node returns 0, which is fine for a new, empty node.
	local currentpressure = meta:get_float(label_pressure)
	if currentpressure > threshold then
		local takenpressure = outputfn(pos, node, currentpressure)
		local newpressure = currentpressure - takenpressure
		if newpressure < 0 then currentpressure = 0 end
		meta:set_float(label_pressure, newpressure)
	end
end
