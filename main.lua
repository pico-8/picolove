--[[
Implementation of PICO8 API for LOVE
]]

local scale = 4
local xpadding = 34
local ypadding = 14
local __accum = 0

local __pico_pal_draw = {
}

local __pico_pal_display = {
}

local __pico_pal_transparent = {
	[0] = false
}

local __pico_palette = {
	[0] = {0,0,0,255},
	{29,43,83,255},
	{126,37,83,255},
	{0,135,81,255},
	{171,82,54,255},
	{95,87,79,255},
	{194,195,199,255},
	{255,241,232,255},
	{255,0,77,255},
	{255,163,0,255},
	{255,255,39,255},
	{0,231,86,255},
	{41,173,255,255},
	{131,118,156,255},
	{255,119,168,255},
	{255,204,170,255}
}



local __pico_camera_x = 0
local __pico_camera_y = 0

function love.load(argv)
	love_args = argv
	love.window.setMode(128*scale+xpadding*2,128*scale+ypadding*2)
	love.graphics.setDefaultFilter('nearest','nearest')
	__screen = love.graphics.newCanvas(128,128)

	local font = love.graphics.newImageFont("font.png","abcdefghijklmnopqrstuvwxyz\"'`-_/1234567890!?[](){}.,;:<> ")
	love.graphics.setFont(font)
	font:setFilter('nearest','nearest')

	love.mouse.setVisible(false)
	love.window.setTitle("pico-8-emu")
	love.graphics.setLineStyle('rough')
	love.graphics.setPointStyle('rough')
	love.graphics.setPointSize(1)
	love.graphics.setLineWidth(1)

	love.graphics.origin()
	love.graphics.setCanvas(__screen)
	love.graphics.setScissor(0,0,127,127)

	__shader_palette_data = love.image.newImageData(16,1)
	__shader_palette = love.graphics.newImage(__shader_palette_data)

	for i=0,15 do
		__shader_palette_data:setPixel(i,0,unpack(__pico_palette[i]))
	end
	__sprite_shader = love.graphics.newShader([[
//extern Image palette;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
	vec4 texcolor = Texel(texture, texture_coords);
	if(texcolor.r == 0 && texcolor.g == 0 && texcolor.b == 0) {
		return vec4(0,0,0,0);
	}
	return texcolor * color;
}]])

	--__sprite_shader:send('palette',__shader_palette)


	-- load the cart
	load_p8(argv[2])
	if _init then _init() end
end

function load_p8(filename)
	loveprint("Opening",filename)
	local f = love.filesystem.newFile(filename,'r')
	if not f then
		error("Unable to open",filename)
	end
	local data,size = f:read()
	f:close()

	if not data then
		error("invalid cart")
	end

	--local start = data:find("pico-8 cartridge // http://www.pico-8.com\nversion ")
	local header = "pico-8 cartridge // http://www.pico-8.com\nversion "
	local start = data:find("pico%-8 cartridge // http://www.pico%-8.com\nversion ")
	if start == nil then
		error("invalid cart")
	end
	local next_line = data:find("\n",start+#header)
	local version_str = data:sub(start+#header,next_line-1)
	local version = tonumber(version_str)
	loveprint("version",version)
	-- extract the lua
	local lua_start = data:find("__lua__") + 8
	local lua_end = data:find("__gfx__") - 1

	local lua = data:sub(lua_start,lua_end)

	-- patch the lua
	lua = lua:gsub("!=","~=")
	-- rewrite assignment operators
	lua = lua:gsub("(%S+)%s*([%+-%*/])=","%1 = %1 %2 ")
	-- rewrite shorthand if statements eg. if (not b) i=1 j=2
	--lua = lua:gsub("if%s*%(([^\n]+)%)%s+([^\n]+)\n",function(a,b)
	--	local c = b:sub(1,5)
	--	loveprint("'"..c.."'")
	--	if c == "then " or c == "then" or c == "then\t" then
	--		return "if "..a.." "..b.."\n"
	--	else
	--		return "if "..a.." then "..b.." end\n"
	--	end
	--end)

	local ok,f,e = pcall(loadstring,lua)
	if not ok or f==nil then
		error("Error loading lua: "..tostring(e))
	else
		local result
		ok,result = pcall(f)
		if not ok then
			error("Error running lua: "..tostring(result))
		else
			loveprint("Ran lua")
		end
	end

	-- load the sprites into an imagedata
	-- generate a quad for each sprite index
	local gfx_start = data:find("__gfx__") + 8
	local gfx_end = data:find("__gff__") - 1
	local gfxdata = data:sub(gfx_start,gfx_end)

	local row = 0
	local tile_row = 32
	local tile_col = 0
	local col = 0
	local sprite = 0
	local tiles = 0
	local shared = 0

	__pico_map = {}
	__pico_quads = {}
	for y=0,63 do
		__pico_map[y] = {}
	end
	__pico_spritesheet_data = love.image.newImageData(128,128)

	local next_line = 1
	while next_line do
		local end_of_line = gfxdata:find("\n",next_line)
		if end_of_line == nil then break end
		end_of_line = end_of_line - 1
		local line = gfxdata:sub(next_line,end_of_line)
		for i=1,#line do
			local v = line:sub(i,i)
			v = tonumber(v,16)
			__pico_spritesheet_data:setPixel(col,row,unpack(__pico_palette[v]))

			if row >= 64 and i%2 == 0 then
				local v = line:sub(i,i+1)
				v = tonumber(v,16)
				__pico_map[tile_row][tile_col] = v
				shared = shared + 1
				tile_col = tile_col + 1
				if tile_col == 128 then
					tile_col = 0
					tile_row = tile_row + 1
				end
			end

			col = col + 1
			if col == 128 then
				col = 0
				row = row + 1
			end
		end
		next_line = gfxdata:find("\n",end_of_line)+1
	end

	for y=0,15 do
		for x=0,15 do
			__pico_quads[sprite] = love.graphics.newQuad(8*x,8*y,8,8,128,128)
			sprite = sprite + 1
		end
	end

	assert(shared == 128 * 32,shared)
	assert(sprite == 256,sprite)

	__pico_spritesheet = love.graphics.newImage(__pico_spritesheet_data)
	__pico_spritesheet_data:encode('spritesheet.png')

	-- load the sprite flags
	__pico_spriteflags = {}

	local gff_start = data:find("__gff__") + 8
	local gff_end = data:find("__map__") - 1
	local gffdata = data:sub(gff_start,gff_end)

	local sprite = 0

	local next_line = 1
	while next_line do
		local end_of_line = gffdata:find("\n",next_line)
		if end_of_line == nil then break end
		end_of_line = end_of_line - 1
		local line = gffdata:sub(next_line,end_of_line)
		if version <= 2 then
			for i=1,#line do
				local v = line:sub(i)
				v = tonumber(v,16)
				__pico_spriteflags[sprite] = v
				sprite = sprite + 1
			end
		else
			for i=1,#line,2 do
				local v = line:sub(i,i+1)
				v = tonumber(v,16)
				__pico_spriteflags[sprite] = v
				sprite = sprite + 1
			end
		end
		next_line = gfxdata:find("\n",end_of_line)+1
	end

	assert(sprite == 256,"wrong number of spriteflags:"..sprite)

	-- convert the tile data to a table

	local map_start = data:find("__map__") + 8
	local map_end = data:find("__sfx__") - 1
	local mapdata = data:sub(map_start,map_end)

	local row = 0
	local col = 0

	local next_line = 1
	while next_line do
		local end_of_line = mapdata:find("\n",next_line)
		if end_of_line == nil then
			loveprint("reached end of map data")
			break
		end
		end_of_line = end_of_line - 1
		local line = mapdata:sub(next_line,end_of_line)
		for i=1,#line,2 do
			local v = line:sub(i,i+1)
			v = tonumber(v,16)
			if col == 0 then
			end
			__pico_map[row][col] = v
			col = col + 1
			tiles = tiles + 1
			if col == 128 then
				col = 0
				row = row + 1
			end
		end
		next_line = mapdata:find("\n",end_of_line)+1
	end
	assert(tiles + shared == 128 * 64,string.format("%d + %d != %d",tiles,shared,128*64))

	-- check all the data is there
	for y=0,63 do
		for x=0,127 do
			assert(__pico_map[y][x],string.format("missing map data: %d,%d",x,y))
		end
	end
end

function love.update(dt)
	__accum = __accum + dt
	if __accum > 1/30 then
		if _update then _update() end
	end
end

function love.run()
	if love.math then
		love.math.setRandomSeed(os.time())
		for i=1,3 do love.math.random() end
	end

	if love.event then
		love.event.pump()
	end

	if love.load then love.load(arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt = 0

	-- Main loop time.
	while true do
		-- Process events.
		if love.event then
			love.event.pump()
			for e,a,b,c,d in love.event.poll() do
				if e == "quit" then
					if not love.quit or not love.quit() then
						if love.audio then
							love.audio.stop()
						end
						return
					end
				end
				love.handlers[e](a,b,c,d)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then
			love.timer.step()
			dt = dt + love.timer.getDelta()
		end

		-- Call update and draw
		local render = false
		while dt > 1/30 do
			if love.update then love.update(1/30) end -- will pass 0 if love.timer is disabled
			dt = dt - 1/30
			render = true
		end

		if render and love.window and love.graphics and love.window.isCreated() then
			love.graphics.origin()
			if love.draw then love.draw() end
			love.graphics.present()
		end

		if love.timer then love.timer.sleep(0.001) end
	end
end

function love.draw()
	love.graphics.setCanvas(__screen)
	love.graphics.setScissor(0,0,127,127)
	love.graphics.origin()
	love.graphics.translate(__pico_camera_x,__pico_camera_y)
	if _draw then _draw() end
--	local i = 0
--	for y=0,15 do
--		for x=0,15 do
--			spr(i,x,y)
--			i=i+1
--		end
--	end
	love.graphics.setCanvas()
	love.graphics.origin()
	love.graphics.setColor(255,255,255,255)
	love.graphics.setScissor()
	love.graphics.draw(__screen,xpadding,ypadding,0,scale,scale)
end

function love.keypressed(key)
	if key == 'r' and love.keyboard.isDown('lctrl') then
		if _init then _init() end
	end
end

function rgb2i(r,g,b,a)
	-- returns 0..15, throws an error if not a valid colour
	if     r ==   0 and g ==   0 and b ==   0 then return 0
	elseif r ==  29 and g ==  43 and b ==  83 then return 1
	elseif r == 126 and g ==  37 and b ==  83 then return 2
	elseif r ==   0 and g == 135 and b ==  81 then return 3
	elseif r == 171 and g ==  82 and b ==  54 then return 4
	elseif r ==  95 and g ==  87 and b ==  79 then return 5
	elseif r == 194 and g == 195 and b == 199 then return 6
	elseif r == 255 and g == 241 and b == 232 then return 7
	elseif r == 255 and g ==   0 and b ==  77 then return 8
	elseif r == 255 and g == 163 and b ==   0 then return 9
	elseif r == 255 and g == 255 and b ==  39 then return 10
	elseif r ==   0 and g == 231 and b ==  86 then return 11
	elseif r ==  41 and g == 173 and b == 255 then return 12
	elseif r == 131 and g == 118 and b == 156 then return 13
	elseif r == 255 and g == 119 and b == 168 then return 14
	elseif r == 255 and g == 204 and b == 170 then return 15
	end
end

function i2rgb(i)
	return __pico_palette[i]
end

function music()
	-- STUB
end

function sfx()
	-- STUB
end

function clip(x,y,w,h)
	if x then
		love.graphics.setScissor(x,y,w,h)
	else
		love.graphics.setScissor(0,0,127,127)
	end
end

function pget(x,y)
	if x >= 0 and x < 128 and y >= 0 and y < 128 then
		return rgb2i(__screen:getImageData():getPixel(flr(x),flr(y)))
	else
		return nil
	end
end

function pset(x,y,c)
	if not c then return end
	color(c)
	__screen:renderTo(function() love.graphics.point(x,y,unpack(__pico_palette[flr(c)%16])) end)
end

function sget(x,y)
	-- return the color from the spritesheet
	return rgb2i(__pico_spritesheet_data:getPixel(x,y))
end

function sset(x,y,c)
end

function fget(n,f)
	if n == nil then return nil end
	if f ~= nil then
		-- return just that bit as a boolean
		return band(__pico_spriteflags[n],shl(1,f)) ~= 0
	end
	return __pico_spriteflags[n]
end

function fset(n,f,v)
	if v == nil then
		v,f = f,nil
	end
	if f then
		__pico_spriteflags[n] = bor(__pico_spriteflags[n],shl(1,v))
	else
		__pico_spriteflags[n] = v
	end
end

function flip()
end

loveprint = print
function print(str,x,y,col)
	if col then color(col) end
	love.graphics.print(str,flr(x),flr(y))
end

function cursor(x,y)
	__pico_cursor = {x,y}
end

function color(c)
	c = flr(c)
	assert(c >= 0 and c < 16,string.format("c is %s",c))
	__pico_color = c
	love.graphics.setColor(__pico_palette[c])
end

function cls()
	__screen:clear(0,0,0,255)
end

function camera(x,y)
	if x ~= nil then
		love.graphics.origin()
		love.graphics.translate(-flr(x),-flr(y))
		__pico_camera_x = flr(x)
		__pico_camera_y = flr(y)
	else
		love.graphics.origin()
		__pico_camera_x = 0
		__pico_camera_y = 0
	end
end

function circ(x,y,r,col)
	col = col or __pico_color
	color(col)
	love.graphics.circle("line",x,y,r,32)
end

function circfill(ox,oy,r,col)
	col = col or __pico_color
	color(col)
	--love.graphics.circle("fill",flr(x),flr(y)+0.5,flr(r)+0.5,32)
	local r2 = r*r
	for y=-r,r do
		for x=-r,r do
			if x*x+y*y <= r2 + r*0.8 then
				love.graphics.point(ox+x,oy+y)
			end
		end
	end
end

function line(x0,y0,x1,y1,col)
	col = col or __pico_color
	color(col)
	--love.graphics.line(flr(x0),flr(y0),flr(x1),flr(y1))
	--love.graphics.line(flr(x0)+0.375,flr(y0)+0.375,flr(x1)+0.375,flr(y1)+0.375)
	--love.graphics.line(flr(x0)+0.5,flr(y0)+0.5,flr(x1)+0.5,flr(y1)+0.5)
	_line(x0,y0,x1,y1,col)
end

function _line(x0,y0,x1,y1,col)
	col = col or __pico_color
	color(col)

	x0 = flr(x0)
	y0 = flr(y0)
	x1 = flr(x1)
	y1 = flr(y1)

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	if dy < 0 then
		dy = -dy
		stepy = -1
	else
		stepy = 1
	end
	
	if dx < 0 then
		dx = -dx
		stepx = -1
	else
		stepx = 1
	end
	
	love.graphics.point(x0,y0)
	if dx > dy then
		local fraction = dy - bit.rshift(dx, 1)
		while x0 ~= x1 do
			if fraction >= 0 then
				y0 = y0 + stepy
				fraction = fraction - dx
			end
			x0 = x0 + stepx
			fraction = fraction + dy
			love.graphics.point(flr(x0),flr(y0))
		end
	else
		local fraction = dx - bit.rshift(dy, 1)
		while y0 ~= y1 do
			if fraction >= 0 then
				x0 = x0 + stepx
				fraction = fraction - dy
			end
			y0 = y0 + stepy
			fraction = fraction + dx
			love.graphics.point(flr(x0),flr(y0))
		end
	end
end

function rect(x0,y0,x1,y1,col)
	col = col or __pico_color
	color(col)
	love.graphics.rectangle("line",x0,y0,x1-x0+1,y1-y0+1)
end

function rectfill(x0,y0,x1,y1,col)
	col = col or __pico_color
	color(col)
	love.graphics.rectangle("fill",x0,y0,x1-x0+1,y1-y0+1)
end

function run()
	love.load(love_args)
end

function reload()
end

function pal(c0,c1,p)
	if c0 == nil then
		-- reset palette
		__pico_pal_display = {}
		__pico_pal_draw = {}
		return
	end
	if p == 1 then
		__pico_pal_display[c0] = c1
	else
		__pico_pal_draw[c0] = c1
	end
end

function palt(c,t)
	if c == nil then
		__pico_pal_transparent = { [0] = false }
	else
		if t == false then
			__pico_pal_transparent[c] = false
		else
			__pico_pal_transparent[c] = nil
		end
	end
end

function spr(n,x,y,w,h,flip_x,flip_y)
	love.graphics.setShader(__sprite_shader)
	love.graphics.setColor(255,255,255,255)
	love.graphics.draw(__pico_spritesheet,__pico_quads[flr(n)],flr(x),flr(y),0)
	love.graphics.setShader()
end

function sspr(sx,sy,sw,sh,dx,dy,dw,dh,flip_x,flip_y)
	dw = dw or sw
	dh = dh or sh
	local q = love.graphics.newQuad(sx,sy,sw,sh,128,128)
	love.graphics.setShader(__sprite_shader)
	love.graphics.setColor(255,255,255,255)
	love.graphics.draw(__pico_spritesheet,q,flr(dx),flr(dy),0,dw/sw,dh/sh)
	love.graphics.setShader()
end

function add(a,v)
	table.insert(a,v)
end

function del(a,dv)
	for i,v in ipairs(a) do
		if v==dv then
			table.remove(a,i)
		end
	end
end

function foreach(a,f)
	for i,v in ipairs(a) do
		f(v)
	end
end

function count(a)
	return #a
end

function all(a)
	local i = 0
	local n = table.getn(a)
	return function()
		i = i + 1
		if i <= n then return a[i] end
	end
end

local __pico_keypressed = {
	[0] = {},
	[1] = {}
}

local __keymap = {
	[0] = {
		[0] = 'left',
		[1] = 'right',
		[2] = 'up',
		[3] = 'down',
		[4] = 'z',
		[5] = 'x',
	},
	[1] = {
		[4] = 'escape',
	}
}

function btn(i,p)
	p = p or 0
	if __keymap[p][i] then
		return love.keyboard.isDown(__keymap[p][i])
	end
end



function btnp(i,p)
	p = p or 0
	if __keymap[p][i] then
		local id = love.keyboard.isDown(__keymap[p][i])
		if __pico_keypressed[p][i] and __pico_keypressed[p][i] > 0 then
			__pico_keypressed[p][i] = __pico_keypressed[p][i] - 1
			return false
		end
		if id then
			__pico_keypressed[p][i] = 12
			return true
		end
	end
end

function sfx(n,channel,offset)
end

function music(n,fade_len,channel_mask)
end

function mget(x,y)
	if x == nil or y == nil then return nil end
	if y > 63 or x > 127 or x < 0 or y < 0 then return nil end
	return __pico_map[flr(y)][flr(x)]
end

function mset(x,y,v)
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		__pico_map[flr(y)][flr(x)] = v
	end
end

function map(cel_x,cel_y,sx,sy,cel_w,cel_h,bitmask)
	love.graphics.setShader(__sprite_shader)
	love.graphics.setColor(255,255,255,255)
	for y=cel_y,cel_y+cel_h do
		if y < 64 and y >= 0 then
			for x=cel_x,cel_x+cel_w do
				if x < 128 and x >= 0 then
					local v = __pico_map[y][x]
					assert(v,string.format("v = nil, %d,%d",x,y))
					if bitmask == nil or (bitmask and band(__pico_spriteflags[v],bitmask) ~= 0) then
						--love.graphics.draw(__pico_spritesheet,__pico_quads[v],sx-__pico_camera_x+8*x,sy-__pico_camera_y+8*y)
						love.graphics.draw(__pico_spritesheet,__pico_quads[v],sx+8*x,sy+8*y)
					end
				end
			end
		end
	end
	love.graphics.setShader()
end

-- memory functions excluded

function memcpy(dest_addr,source_addr,len)
	-- only for range 0x6000+0x8000
	if source_addr >= 0x6000 and dest_addr >= 0x6000 then
		if source_addr + len >= 0x8000 then
			return
		end
		if dest_addr + len >= 0x8000 then
			return
		end
		local img = __screen:getImageData()
		for i=1,len do
			local x = flr(source_addr-0x6000+i)%128
			local y = flr((source_addr-0x6000+i)/64)
			local c = rgb2i(img:getPixel(x,y))

			local dx = flr(dest_addr-0x6000+i)%128
			local dy = flr((dest_addr-0x6000+i)/64)
			pset(dx,dy,c)
		end
	end
end

function peek(...)
end

function poke(...)
end

max = math.max
min = math.min
function mid(x,y,z)
	return x > y and x or y > z and z or y
end

assert(mid(1,5,6) == 5)
assert(mid(3,2,6) == 3)
assert(mid(3,9,6) == 6)

function __pico_angle(a)
	-- FIXME: why does this work?
	return (((a - math.pi) / (math.pi*2)) + 0.25) % 1.0
end

flr = math.floor
cos = function(x) return math.cos(x*(math.pi*2)) end
sin = function(x) return math.sin(-x*(math.pi*2)) end
atan2 = function(y,x) return __pico_angle(math.atan2(y,x)) end

sqrt = math.sqrt
abs = math.abs
rnd = function(x) return love.math.random()*x end
srand = love.math.randomseed
sgn = function(x)
	if x < 0 then
		return -1
	elseif x > 0 then
		return 1
	else
		return 0
	end
end

local bit = require("bit")

band = bit.band
bor = bit.bor
bxor = bit.bxor
bnot = bit.bnot
shl = bit.lshift
shr = bit.rshift

sub = string.sub

mapdraw = map
