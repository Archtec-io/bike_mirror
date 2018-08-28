--
-- Helper functions
--

local function is_water(pos)
	local nn = minetest.get_node(pos).name
	return minetest.get_item_group(nn, "liquid") ~= 0
end


local function get_sign(i)
	if i == 0 then
		return 0
	else
		return i / math.abs(i)
	end
end


local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end


local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

--
-- bike entity
--

local bike = {
	physical = true,
	-- Warning: Do not change the position of the collisionbox top surface,
	-- lowering it causes the bike to fall through the world if underwater
	collisionbox = {-0.4, -0.4, -0.4, 0.4, 0.8, 0.4},
	visual = "mesh",
	mesh = "bike_bike.obj",
	textures = {"bike_bike.png"},
	stepheight = 0.6,

	driver = nil,
	old_driver = nil,
	v = 0,
	last_v = 0,
	removed = false
}

local function dismount_player(bike)
	local name = bike.driver:get_player_name()
	bike.object:set_velocity({x = 0, y = 0, z = 0})
	bike.v = 0

	bike.old_driver = bike.driver
	bike.driver = nil
	bike.old_driver:set_detach()
	default.player_attached[name] = false
	--default.player_set_animation(bike.old_driver, "stand" , 30)
	local pos = bike.old_driver:get_pos()
	pos = {x = pos.x, y = pos.y + 0.2, z = pos.z}
	minetest.after(0.1, function()
		bike.old_driver:set_pos(pos)
	end)
end

function bike.on_rightclick(self, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local name = clicker:get_player_name()
	if self.driver and clicker == self.driver then
		dismount_player(self)
	elseif not self.driver then
		local attach = clicker:get_attach()
		if attach and attach:get_luaentity() then
			local luaentity = attach:get_luaentity()
			if luaentity.driver then
				luaentity.driver = nil
			end
			clicker:set_detach()
		end
		self.driver = clicker
		clicker:set_attach(self.object, "",
			{x = 0, y = 1.3, z = -2.3}, {x = 0, y = 0, z = 0})
		default.player_attached[name] = true
		--[[minetest.after(0.2, function()
			default.player_set_animation(clicker, "sit" , 30)
		end)--]]
		clicker:set_look_horizontal(self.object:get_yaw())
	end
end


function bike.on_activate(self, staticdata, dtime_s)
	self.object:set_acceleration({x = 0, y = -9.8, z = 0})
	self.object:set_armor_groups({immortal = 1})
	if staticdata then
		self.v = tonumber(staticdata)
	end
	self.last_v = self.v
end


function bike.get_staticdata(self)
	return tostring(self.v)
end


function bike.on_punch(self, puncher)
	if not puncher or not puncher:is_player() or self.removed then
		return
	end
	if self.driver and puncher == self.driver then
		self.driver = nil
		puncher:set_detach()
		default.player_attached[puncher:get_player_name()] = false
	end
	if not self.driver then
		self.removed = true
		local inv = puncher:get_inventory()
		if not (creative and creative.is_enabled_for
				and creative.is_enabled_for(puncher:get_player_name()))
				or not inv:contains_item("main", "bike:bike") then
			local leftover = inv:add_item("main", "bike:bike")
			-- if no room in inventory add a replacement bike to the world
			if not leftover:is_empty() then
				minetest.add_item(self.object:get_pos(), leftover)
			end
		end
		-- delay remove to ensure player is detached
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end
end


function bike.on_step(self, dtime)
	if self.object:get_velocity().y < -10 and self.driver ~= nil then
		dismount_player(self)
		return
	end

	local current_v = get_v(self.object:get_velocity()) * get_sign(self.v)
	self.v = (current_v + self.v*3) / 4
	if self.driver then
		local ctrl = self.driver:get_player_control()
		local yaw = self.object:get_yaw()
		local agility = 0

		if self.v > 0.4 then
			agility = 1/math.sqrt(self.v)
		else
			agility = 1.58
		end

		if ctrl.up then
			self.v = self.v + 0.2 * agility
		elseif ctrl.down then
			self.v = self.v - 0.5 * agility
		else
			self.v = self.v - 0.05 * agility
		end

		if ctrl.left then
			self.object:set_yaw(yaw + (1 + dtime) * 0.06 * agility)
		elseif ctrl.right then
			self.object:set_yaw(yaw - (1 + dtime) * 0.06 * agility)
		end
	end
	local velo = self.object:get_velocity()
	if self.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		self.object:move_to(self.object:get_pos())
		return
	end
	local s = get_sign(self.v)
	if s ~= get_sign(self.v) then
		self.object:set_velocity({x = 0, y = 0, z = 0})
		self.v = 0
		return
	end
	if self.v > 10 then
		self.v = 10
	elseif self.v < 0 then
		self.v = 0
	end

	local p = self.object:get_pos()
	if is_water(p) then
		self.v = self.v / 1.3
	end

	local new_velo
	new_velo = get_velocity(self.v, self.object:get_yaw(), self.object:get_velocity().y)
	self.object:move_to(self.object:get_pos())
	self.object:set_velocity(new_velo)
end


minetest.register_entity("bike:bike", bike)


minetest.register_craftitem("bike:bike", {
	description = "bike",
	inventory_image = "bike_inventory.png",
	--wield_image = "bike_wield.png",
	wield_scale = {x = 3, y = 3, z = 2},
	liquids_pointable = true,
	groups = {flammable = 2},

	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local udef = minetest.registered_nodes[node.name]
		if udef and udef.on_rightclick and
				not (placer and placer:is_player() and
				placer:get_player_control().sneak) then
			return udef.on_rightclick(under, node, placer, itemstack,
				pointed_thing) or itemstack
		end

		if pointed_thing.type ~= "node" then
			return itemstack
		end

		bike = minetest.add_entity(pointed_thing.above, "bike:bike")
		if bike then
			if placer then
				bike:set_yaw(placer:get_look_horizontal())
			end
			local player_name = placer and placer:get_player_name() or ""
			if not (creative and creative.is_enabled_for and
					creative.is_enabled_for(player_name)) then
				itemstack:take_item()
			end
		end
		return itemstack
	end,
})


--[[minetest.register_craft({
	output = "bike:bike",
	recipe = {
		{"",           "",           ""          },
		{"group:wood", "",           "group:wood"},
		{"group:wood", "group:wood", "group:wood"},
	},
})

minetest.register_craft({
	type = "fuel",
	recipe = "bike:bike",
	burntime = 20,
})--]]
