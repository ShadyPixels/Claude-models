local fs = require("@lune/fs")
local luau = require("@lune/luau")
local root = "roblox/scripts/"
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local p = dir .. name
		if fs.isDir(p) then walk(p .. "/") elseif name:match("%.lua$") then
			local ok, err = pcall(luau.compile, fs.readFile(p))
			print(ok and "ok  " or "FAIL", p:sub(#root + 1), ok and "" or tostring(err))
		end
	end
end
walk(root)
