-- "addons\\urf_plib\\lua\\includes\\init.lua"
-- Retrieved by https://github.com/lewisclark/glua-steal

do
do
local DOWNLOADFILTER_IS_NONE = GetConVar("cl_downloadfilter"):GetString() == "none"

if (function()

local string_gsub = string.gsub
local debug_getinfo = debug.getinfo
local CompileString = CompileString
local __CompileFile = CompileFile

local vfs, vfsLCL = {}, {}
local autorefreshed = {GLUAPACK_AUTOREFRESH}

local flags = FCVAR_REPLICATED + FCVAR_DONTRECORD + FCVAR_PROTECTED + FCVAR_UNREGISTERED + FCVAR_UNLOGGED
local name = CreateConVar("gluapack_file", "", flags):GetString()
local md5 = CreateConVar("gluapack_md5", "", flags):GetString()
local key = CreateConVar("gluapack_key", "", flags):GetString()
local salt = util.Base64Decode(CreateConVar("gluapack_salt", "", flags):GetString())

print("\n" .. md5)
print("https://gluapack.com")
print("Made with <3 by Billy & friends\n")

local function helpLink()
	local function urlencode(str)
		str = string.gsub(str, "([^%w%-%_%.%~])", function(hex) return string.format("%%%02X", string.byte(hex)) end)
		return str
	end
	local sv_downloadurl = GetConVar("sv_downloadurl")
	if sv_downloadurl then
		sv_downloadurl = string.gsub(string.gsub(sv_downloadurl:GetString() or "", "^%s+", ""), "%s+$", "")
		return "https://gluapack.com/help/?u=" .. urlencode(sv_downloadurl:gsub("/$", "") .. "/data/gluapack/" .. name .. ".bsp.bz2")
	else
		return "https://gluapack.com/help/?u=EMPTY"
	end
end

local succ, halp = pcall(helpLink)
if not succ then
	halp = "https://gluapack.com/help/?u=LUAERROR"
end

local function failed(msg, disconnect, openhelp)
	if disconnect then
		function gluapack() return function() end end
		ErrorNoHalt(msg .. "\n" .. "You have been disconnected from the server because " .. disconnect .. "\n" .. halp .. "\n")
		if openhelp then gui.OpenURL(halp) end
	else
		function gluapack()
			ErrorNoHalt(msg .. "\n" .. halp .. "\n")
			if openhelp then gui.OpenURL(halp) end
			_G.gluapack = function() end
			return function() end
		end
	end
end

if #md5 == 0 or #name == 0 then
	failed("gluapack isn't active (the server didn't send us the ConVars) but a script still tried to invoke gluapack - bug?")
	print("gluapack ABORTED - looks like gluapack isn't active")
	return
end

-- https://github.com/philanc/plc/blob/master/plc/rc4.lua
local function rc4(key, plain)
	local function step(s, i, j)
		i = bit.band(i + 1, 0xff)
		local ii = i + 1
		j = bit.band(j + s[ii], 0xff)
		local jj = j + 1
		s[ii], s[jj] = s[jj], s[ii]
		local k = s[ bit.band(s[ii] + s[jj], 0xff) + 1 ]
		return s, i, j, k
	end
	local s do
		assert(#key == 16, "Key is not a 16-byte string")
		s = {}
		local j,ii,jj
		for i = 0, 255 do s[i+1] = i end
		j = 0
		for i = 0, 255 do
			ii = i+1
			j = bit.band(j + s[ii] + string.byte(key, (i % 16) + 1), 0xff)
			jj = j+1
			s[ii], s[jj] = s[jj], s[ii]
		end
	end
	local i, j = 0, 0
	local k
	local t = {}
	for n = 1, #plain do
		s, i, j, k = step(s, i, j)
		t[n] = string.char(bit.bxor(string.byte(plain, n), k))
	end
	return table.concat(t)
end

local keyBin do
	keyBin = {}
	assert(#key % 2 == 0)
	for i = 1, #key, 2 do
		keyBin[#keyBin + 1] = string.char(tonumber(key:sub(i, i + 1), 16))
	end
	keyBin = table.concat(keyBin)
end

do
	local path = ("download/data/gluapack/%s.bsp"):format(name)

	if not file.Exists(path, "GAME") then
		if DOWNLOADFILTER_IS_NONE then
			failed(
				"You have cl_downloadfilter set to none! It must be a minimum of mapsonly to join this server!",
				"the clientside Lua state cannot be initialized"
			)
		else
			failed(
				"gluapack fatal error - pack file not found (did it fail to download? check your network settings!)",
				"the clientside Lua state cannot be initialized",
				true
			)
		end
		return true
	end

	local contents do
		local f = file.Open(path, "rb", "GAME")
		contents = f:Read(f:Size())
		f:Close()

		contents = rc4(keyBin, contents, 0):sub(257)
		assert(contents ~= nil and #contents > 0, "Decryption failed")

		contents = util.Decompress(contents)
		assert(contents ~= nil and #contents > 0, "Decompression failed")

		local fileMD5 = util.MD5(contents)
		if fileMD5 ~= md5 then
			failed(
				("gluapack fatal error - pack MD5 does not match up (%s (yours) != %s (server's))\n"):format(fileMD5, md5),
				"for security reasons"
			)
			return true
		end

		contents = contents:sub(2) -- Skip the version byte
	end

	local function hex(bytes)
		local hex = {}
		for i = 1, #bytes do
			hex[i] = string.format("%02x", string.byte(bytes, i, i))
		end
		return table.concat(hex)
	end

	local i = 1
	while i < #contents do
		local vfs1 = hex(contents:sub(i, i + 15))
		i = i + 16

		local lcl1 = hex(contents:sub(i, i + 15))
		i = i + 16

		local lcl2 = hex(contents:sub(i, i + 15))
		i = i + 16

		local len = tonumber(hex(contents:sub(i, i + 3)), 16)
		assert(len < #contents, "u32 decoding error")
		i = i + 4

		local contents = contents:sub(i, i + (len - 1))
		i = i + len

		vfs[vfs1] = contents
		vfsLCL[lcl1] = contents
		vfsLCL[lcl2] = contents
	end
end

local function saltedMD5(val)
	return util.MD5(salt .. val)
end

function gluapack()
	local info = debug_getinfo(2, "S")
	info = string_gsub(info.source, "^@", "")
	local md5 = saltedMD5(info)
	if vfs[md5] then
		return CompileString(vfs[md5], info)
	else
		ErrorNoHaltWithStack(("gluapack: missing file in VFS? %s (%s)"):format(info, md5))
	end
end

function CompileFile(path, src)
	local md5 = saltedMD5(path)
	if vfsLCL[md5] then
		return CompileString(vfsLCL[md5], src or path)
	else
		return __CompileFile(path, src)
	end
end

local function removeFromVFS(path)
	print(("gluapack: removing %s from VFS (autorefresh)"):format(path))
	vfs[saltedMD5(path)] = nil
	vfsLCL[saltedMD5(path:gsub("^addons/[^/]+/", ""):gsub("^gamemodes/[^/]+/entities/", ""):gsub("^gamemodes/", ""):gsub("^lua/", ""))] = nil
	vfsLCL[saltedMD5(path:gsub("^addons/[^/]+/", ""):gsub("^gamemodes/", ""):gsub("^lua/", ""))] = nil
end

for _, path in ipairs(autorefreshed) do
	removeFromVFS(path)
end

timer.Create("gmsv_gluapack_net", 0, 0, function()
	if not net or not net.Receive then return end
	timer.Remove("gmsv_gluapack_net")
	net.Receive("gmsv_gluapack_autorefresh", function()
		local path = net.ReadString()
		removeFromVFS(path)
	end)
end)

end)() then goto failed end

goto success

::failed::
if not DOWNLOADFILTER_IS_NONE then
	RunConsoleCommand("disconnect")
end
require("gamemode")
require("scripted_ents")
require("weapons")
do return end

::success::
DOWNLOADFILTER_IS_NONE = nil
end
jit.flush()
collectgarbage() collectgarbage()

end
-- Init
if (SERVER) then
	AddCSLuaFile()
	AddCSLuaFile 'plib/init.lua'
end
include 'plib/init.lua'

plib.IncludeSH '_init.lua'

-- Extensions
for k, v in pairs(plib.LoadDir('extensions')) do
	plib.IncludeSH(v)
end
for k, v in pairs(plib.LoadDir('extensions/server')) do
	plib.IncludeSV(v)
end
for k, v in pairs(plib.LoadDir('extensions/client')) do
	plib.IncludeCL(v)
end