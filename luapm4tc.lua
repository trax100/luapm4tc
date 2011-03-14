#!/bin/lua
--[[
        lpm4tc - Lua Package Manager for TinyCore Linux v0.5
        (c) Wladyslaw Motyka 2011
        TODO:
            rewrite all functions to automatic recognize "file:///..." and "http://www.ibiblio...." protocols
              instead of having "remote and local" functions
              
              
        ROADMAP
          v1
            Export official Repository to lpm4tc repo.
            to be able to Download by lpm4tc
            add Logging
          
          
        UpdateDB    update Sizelist NOT /tce/optional
        UpdateTCE   update /tce/optional
          
        Export functions:
            CheckUpdates( DB )
                RemoteMirror(DB.ts) LocalMirror(DB.ts)
                    parse_sizelist()
                        readRemoteDEP(url)  readLocalDEP(path_filename)
                        readRemoteMD5(url)  readLocalMD5(path_filename)
            genDB( DB, MIRROR )
            UpdateDB()
        
        myExt functions:
            LoadDB()
            Search()
    
    db.lua structure:
        ts = TIMESTAMP of the last downloaded sizelist.gz
        cl = size of the sizelist.gz
        data = {
            size,
            ts,
            md5,
            deps
        }
        
        
        
    Last:
        add 'ts' to all items in the DB     << not working
        update option(fetch)                << not tested
        
    Manifest:
		117 - app=100, X=10, Categories(Network)=7
		nano / app : tty / 
--]]
---------------------------------------
--[[local CATEGORIES = {
[1] = "accessories",
[1] = "multimedia","graphics",
[1] = "office",
[1] = "programing",
[1] = "internet","network"
[1] = "administration",
[1] = ,
[1] = 
[1] = "games",
[1] = "education",
[1] = "drivers",
[1] = "libs",
}--]]
local lfs   = require("lfs")
local io    = require("io")
local http  = require("socket.http")
local ltn12 = require("ltn12")

local type, tinsert, sfind, sgfind, slower, ssub, smatch, sformat, sgsub, sbyte, schar, srep, mfloor = type, table.insert, string.find, string.gfind, string.lower, string.sub, string.match, string.format, string.gsub, string.byte, string.char, string.rep, math.floor
local iwrite = io.write
io.stdout:setvbuf("no")
opts = {
    isINTERACTIVE   = true,
    KERNEL          = "2.6.33.3-tinycore",
    MBdivider       = 1048576,   -- 1048576 = 1024 * 1024
    FREE_SPACE      = 10000000000,
    sep             = "/",
    linesep         = srep("_",79),
    
    is_CHANGED      = false,
    
    sizelist        = "cache/sizelist.gz",
    optional        = "/tce/optional/",  -- to >> optional
    onBoot          = "/tce/onboot.lst",
    installed       = "/opt/.tce_dir.installed",
 
    localMirror     = "/tcz/",
    MIRRORS         = {
        -- {"file:///C:/_dev/tcz/"},
        {"http://ftp.nluug.nl/os/Linux/distr/tinycorelinux/3.x/tcz/"},
        {"http://ftp.vim.org/os/Linux/distr/tinycorelinux/3.x/tcz/"},
        {"http://distro.ibiblio.org/pub/linux/distributions/tinycorelinux/3.x/tcz/"},  -- DON'T USE
        {"http://sunsite2.icm.edu.pl/pub/Linux/sunsite.unc.edu/distributions/tinycorelinux/3.x/tcz/"},   -- OLD
        {"http://ftp.cc.uoc.gr/mirrors/linux/tinycorelinux/3.x/tcz/"},

        -- {"ftp://ftp.nluug.nl/os/Linux/distr/tinycorelinux/3.x/tcz/"},
        -- {"ftp://ftp.vim.org/os/Linux/distr/tinycorelinux/3.x/tcz/"},
        -- {"ftp://distro.ibiblio.org/pub/linux/distributions/tinycorelinux/3.x/tcz/"},  -- slow
        -- {"ftp://sunsite2.icm.edu.pl/pub/Linux/sunsite.unc.edu/distributions/tinycorelinux/3.x/tcz/"},   -- OLD
        -- {"ftp://ftp.cc.uoc.gr/mirrors/linux/tinycorelinux/3.x/tcz/"},
    },
}
if os.getenv("OS")=="Windows_NT" then
    opts.windows        = true
    opts.optional       = "c:\\tce\\optional\\"
    opts.onBoot         = "c:\\tce\\onboot.lst"
    opts.installed      = "c:\\tce\\.tce_dir.installed"
    opts.localMirror    = "c:\\tcz\\"
    opts.sep            = "\\"
end

----------------------------------------------------------------------------
--- Parse command line options.
-- @author Lua.org ???
-- @param arg Lua arg table
-- @param options see LuaWiki
-- @return <code>table</code>
-- @usage getopt( arg, options )
function getopt( arg, options )
  local tab, free = {}, free or "nothing"
  for k, v in ipairs(arg) do
    if v:sub( 1, 2) == "--" then
      local x = v:find( "=", 1, true )
      if x then tab[ v:sub( 3, x-1 ) ] = v:sub( x+1 )
      else      tab[ v:sub( 3 ) ] = true
      end
    elseif v:sub( 1, 1 ) == "-" then
      local y = 2
      local l = #v
      local jopt
      while ( y <= l ) do
        jopt = v:sub( y, y )
        if options:find( jopt, 1, true ) then
          if y < l then
            tab[ jopt ] = v:sub( y+1 )
            y = l
          else
            tab[ jopt ] = arg[ k + 1 ]
          end
        else
          tab[ jopt ] = true
        end
        y = y + 1
      end
    else
        free = v
    end
  end
  return tab, free
end
----------------------------------------------------------------------------
function loadtable(filename, empty_tab_string)
    local res, tab = pcall( dofile, filename )   -- old_MASTER
    if not res then
        local f=io.open(filename,"wb"); f:write(empty_tab_string or ""); f:close()
        return loadstring(empty_tab_string)() -- empty OLD_MASTER
    else
        return tab
    end
end
--- Serialise table into string.
-- @author Lua.org ???
-- @param o table to serialize
-- @return string
-- @usage serialize( GAME )
local function serialize(o)
    local s=""
    local to = type(o)
    if to == "number" then
        s=s..o
    elseif to == "string" then
        s=s..sformat("%q", o)
    elseif to == "table" then
        s=s.."{\n"
        for k,v in pairs(o) do
--             if     type(k)=="number" then s=s..'['..k..']=\t'
            if     type(k)=="number" then s=s.."\t"
            elseif type(k)=="string" then
                if sfind(k,"[%p^_]") or smatch(k,"^%d") then s=s..'  ["'..k..'"]=\t'   -- [:.-] >> %p
                else  s=s..'  '..k..'=\t' end
            end
            s=s .. serialize(v)
            s=s..",\n"
        end
        s=s.."}"
    elseif to == "boolean" then
        if o then s=s.."true" else s=s.."false" end
    else
--~         error("cannot serialize a " .. to)
    end
    return s
end
--- Save serialized table into file.
-- @author Lua.org ???
-- @param filename Name of output file
-- @param TAB table to serialize
-- @return string
-- @usage savetable( "save.lua", GAME )
function savetable( filename, TAB )
    local s;
    local function serialize2f (o)
        local to = type(o)
        if to == "number" then
            s:write(o)
        elseif to == "string" then
            s:write(sformat("%q", o))
        elseif to == "table" then
            s:write("{")
            for k,v in pairs(o) do
    --             if     type(k)=="number" then s=s..'['..k..']=\t'
                -- if     type(k)=="number" then s:write(" ")
                if type(k)=="string" then
                    if sfind(k,"[%p^_]") or smatch(k,"^%d") then s:write('["',k,'"]=')   -- [:.-] >> %p
                    else  s:write(k,'=') end
                end
                s:write(serialize2f(v))
                s:write(",")
            end
            s:write("}")
        elseif to == "boolean" then
            if o then s:write("true") else s:write("false") end
        else
    --~         error("cannot serialize a " .. to)
        end
    end ----------------------------------------------------------------------------

    s=io.open( filename, "w" )
    s:write( "--", os.date(), "\nreturn " )
    serialize2f(TAB)
    s:close()
end
function savetable2( filename, TAB )
    local s;
    local function serialize2f (o)
        local to = type(o)
        if to == "number" then
            s:write(o)
        elseif to == "string" then
            s:write(sformat("%q", o))
        elseif to == "table" then
            s:write("{\n")
            for k,v in pairs(o) do
    --             if     type(k)=="number" then s=s..'['..k..']=\t'
                if     type(k)=="number" then s:write("\t")
                elseif type(k)=="string" then
                    if sfind(k,"[%p^_]") or smatch(k,"^%d") then s:write('  ["',k,'"]=\t')   -- [:.-] >> %p
                    else  s:write('  ',k,'=\t') end
                end
                s:write(serialize2f(v))
                s:write(",\n")
            end
            s:write("}")
        elseif to == "boolean" then
            if o then s:write("true") else s:write("false") end
        else
    --~         error("cannot serialize a " .. to)
        end
    end ----------------------------------------------------------------------------

    s=io.open( filename, "w" )
    s:write( "--", os.date(), "\nreturn " )
    serialize2f(TAB)
    s:close()
end
----------------------------------------------------------------------------
local DAT = {Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
function Parse_dati(b)
    return os.time( {day=b:sub(6,7), month=DAT[b:sub(9,11)], year=b:sub(13,16), hour=b:sub(18,19), min=b:sub(21,22), sec=b:sub(24,25) } )   -- Fri, 22 Oct 2010 08:45:52 GMT
end ----------------------------------------------------------------------------
function Parse_dati2(b)
    return os.time( {day=b:sub(1,2), month=DAT[b:sub(4,6)], year=b:sub(8,11), hour=b:sub(13,14), min=b:sub(16,17) } )   -- 12-Nov-2010 10:21
end ----------------------------------------------------------------------------
function RelativeDate(delta)
    if (delta < 60) then
        return mfloor(delta) .. "s"
    else
        local s = mfloor(delta % 60);
        local m = mfloor((delta % 3600)  / 60);
        local h = mfloor((delta % 86400) / 3600);
        local d = mfloor((delta % 31536000) / 86400);
        local y = mfloor(delta / 31536000);

        if y>1 then
            return y.." years"
        elseif y>0 then
            return d.." day"
        elseif d>1 then
            return d.." days"
        elseif d>0 then
            return d.." day"
        else
            return sformat("%02d:%02d:%02d", h, m, s)
        end
    end
end ----------------------------------------------------------------------------
function attrdir (path)
    local t={}
	for file in lfs.dir(path) do
		if file ~= "." and file ~= ".." and file:sub(-4)==".tcz" then
            t[file]=true
		end
	end
    return t
end
function cmd(str)
    local out=io.popen(str)
    local res=out:read("*all")
    out:close()
    return res
end
local function ask(str)
    iwrite(str, " [Y/n] ")
    if io.read()=="Y" then return true end
end
local function checkRoot()
    return "# "
end
local function boxit(str)
    iwrite("+",srep("-",#str+2),"+\n")
    iwrite("| ",tostring(str)," |\n")
    iwrite("+",srep("-",#str+2),"+\n")
end
local function progress(str)
    iwrite(srep("-",#str+3),"\\\n")
    iwrite("  ",tostring(str),"  >\n")
    iwrite(srep("-",#str+3),"/\n")
end
local _OC=os.clock()
local function oc() return sformat("%.1f",os.clock()-_OC) end

local function simpleGet(url)local t={};return t,http.request{url=url,sink=ltn12.sink.table(t)}end
local function bySocket_table(url)
    local t, r, c, h, m = simpleGet(url)
-- print(serialize(h))
    if r==1 and c==200 then
        local ts = Parse_dati(h["last-modified"] or h["date"])
        return t, ts
--    elseif r==1 and c==404 then
--        return t
    elseif c=="timeout" then
        return t
    else
        io.stderr:write(tostring(r)," ",tostring(c)," ",tostring(m))
    end
end
local function bySocket_header(url)
    -- Requests information about a document, without downloading it.
    -- Useful, for example, if you want to display a download gauge and need
    -- to know the size of the document in advance
    local x=os.clock()
    local r, c, h = http.request {
      method = "HEAD",
      url = url
    }
    local x, ts, size = os.clock()-x
    -- print(1,r,c,serialize(h))

    if r==1 and c==200 then
        ts = Parse_dati(h["last-modified"])
        size = tonumber(h["content-length"])
    end
    return x, size, ts
end
local function bySocket_file(url,result_filename)
    local x=os.clock()
    local r, c, h = http.request{ 
        url = url, 
        sink = ltn12.sink.file(io.open(result_filename,"wb"))
    }
    -- print(1,r,c,serialize(h))
    x = os.clock()-x
    if r==1 and c==200 then
        local ts, length = Parse_dati(h["last-modified"]), tonumber(h["content-length"])
        local speed = math.floor((length * (1/x)) / 1024)
        return speed, length, ts
    end
end





local function Search(DBdata,pattern,deep) -- search_word
    -- print("[".. pattern .."]")
    assert(pattern)

    local function showColumns(TAB)
		local size = #TAB[#TAB] +1
		local col = math.floor(80 / size) 
		local c=0
		for n=1, #TAB do
			c=c+1
			iwrite(sformat("%-".. size .."s", TAB[n]))
			if c>col then iwrite('\n'); c=0 end
		end
    end


    local function HighlightInComment(comment,pattern)
        local hc = smatch(slower(comment), sformat("[\n]?([^\n]*%s[^\n]*)\n", slower(pattern)))
        if hc then
            return hc
        else
            -- print( "HighlightInComment() << fail", ssub(comment,0,30))--, schar(7))
            return ""
        end
    end
    local function searchInInfoFile(fn,pattern)
        local f=io.open(sformat("%s%s.tcz.info", opts.localMirror, fn), "r")
        if f then
            local data=f:read("*all")
            f:close()
            local dsc = smatch(data,"Description:%s+([^\n]-)%s-\n") or ""
            local com = smatch(data,"Comments:%s+(.-)\nC") or ""
            if smatch(slower(dsc), slower(pattern)) or smatch(slower(com), slower(pattern)) then
                local hc = HighlightInComment(sgsub(com,"\n%s+","\n"), pattern)
                return {dsc, hc, com, data}
            end
        end
    end

    local function searchPkg(fn,pattern)
        -- exact search
        if DBdata[pattern] then
            iwrite(pattern)
        else
			local T={}
            -- search in pkg filenames
            for pkg in pairs(DBdata)do if pkg:lower():match(pattern)then T[#T+1]=pkg end end
            table.sort(T, function(a,b) return #a<#b end)
            --print(table.concat(T,", "))
            showColumns(T)
        end
    end

    if deep >= 0 then
        searchPkg(pattern,"^".. pattern)
    end

    if deep >= 1 then
        searchPkg(pattern,pattern)
        iwrite("\n")
    end

    if deep >= 2 then
        -- search in pkg filenames
        for pkg in pairs(DBdata) do
            local res = searchInInfoFile(pkg,pattern)
            if res then
                iwrite(sformat("\t%-40s\n\t[ %s ]\n\t '%s'\n\n", pkg, res[1], res[2]))
            end
        end
    end
end


local function recursionDEP( DBdata, pkg )
    local KERNEL = opts.KERNEL
    local DEP = {[pkg]=false}
    local function __rd__(o)
        if type(o) == "table" then
            for n=1,#o do
                local p = sgsub(o[n],"KERNEL$",KERNEL)
                DEP[p]=false
                __rd__(DBdata[p][3])
            end
        end
    end
    __rd__(DBdata[pkg][3])
    return DEP
end
local function compute_NEEDed_free_space( DBdata, DEP )
    local totalsize_needed    = 0
    local totalsize_installed = 0
    for pkg,exist in pairs(DEP) do
        local size = DBdata[pkg][1]
        if DBdata[pkg].installed then
            DEP[pkg]=true
            totalsize_installed = totalsize_installed + size
        else
            totalsize_needed = totalsize_needed + size
        end
    end
    return DEP, totalsize_needed, totalsize_installed
end
local function fetch( DBdata, url, filename )
    if not DBdata[filename] then
        iwrite("not found in the DB(sizelist)\n")
        if ask( sformat("Do you want to search in DB for '%s'?", filename)) then
            Search(DBdata,filename,1)
            return true
        else
            os.exit(2)
        end
    end

    if DBdata[filename].installed then
        print(filename .." is already installed.")
        print("check if there is a NEWER version") --!!!!!!!!!!!!
    else
        local DEP, totalsize_needed, totalsize_installed = compute_NEEDed_free_space( DBdata, recursionDEP( DBdata, filename ) )
        if totalsize_needed >= opts.FREE_SPACE then
            -- totalsize = totalsize_needed + totalsize_installed
            -- iwrite( sformat("\n  %-40s %10d, %6.2f MB\nTotal size (bytes)", totalsize, totalsize / opts.MBdivider) )
            -- iwrite( sformat("+ %-40s %10d, %6.2f MB\nIndicates need to download", totalsize_needed, totalsize_needed / opts.MBdivider))
            if totalsize_needed > opts.FREE_SPACE then error("Not enough free space for this operation! quiting.") end
            print("no free space", totalsize_needed - opts.FREE_SPACE, "bytes missing."); os.exit(11)
        end

        iwrite(sformat("%s\n  Fetching missing dependencies...\n", opts.linesep))
        for pkg,exist in pairs(DEP) do
            if not DBdata[pkg] then
                iwrite("\n\tERROR - ",filename,".tcz.dep ask for ",pkg,".tcz but file didn't exist in the DB(sizelist).\n")
            else
                if not DBdata[pkg].installed then
                    if not exist then
                        iwrite(sformat(" %5s  Fetching %-40s ", oc(), pkg))
                        local speed, length, ts = bySocket_file( sformat("%s%s.tcz", url, pkg), sformat("%s%s.tcz", opts.optional, pkg) )
                        iwrite(sformat(" %s %s %s old\n", speed, length, RelativeDate(os.time()-ts)))
                        
                        --  !!!!  add for all deps???
                        get_Md5_Dep(DBdata[pkg], url, filename, true)
                        
                        DBdata[pkg].installed=true
                        opts.is_CHANGED = true
                    end
                end
            end
        end
    end
end





local function iinfo(DBdata, pkg)
    if not DBdata[pkg] then
		print(pkg, "not exist.")
		Search(DBdata, pkg, 0)
		return
	end
    os.remove("info.lst")
    bySocket_file(opts.MIRRORS[1][1] .. pkg ..".tcz.info", "info.lst")
    local f=io.open("info.lst","r")
    local data=f:read("*all")
    f:close()
    local Description, Version = smatch(data,"Description:%s+([^\r\n]+)[\r\n]-Version:%s+([^\r\n]+)[\r\n]")
    if not Description or not Version then print("error parsing info.lst:", data,"------\n") else
		print("Description:", Description)
		print("Version:", Version)
	end
	if ask("  Wanna see more info?") then print(); print(data) end
end
local function readLocal_Ts(path_filename)
    local at = lfs.attributes(sizelist)
    if not at then
        return ""    -- missing local file
    end
    return at.modification
end
local function readLocalMD5(path_filename) -- 7d2607bb269d738ab14b50751af186ea  libatomic_ops.tcz
    local f=io.open(path_filename,"r")
    if not f then
        return ""    -- missing local file / add WGET
    else
        local text=f:read("*line")
        local md5 = smatch(text, "^(%x+)%s")
        f:close()
        return md5
    end
end
local function readLocalDEP(path_filename)
    local f=io.open(path_filename,"r")
    if not f then
        return ""    -- missing local file / add WGET
    else
        local DEP = {}
        while true do
            local line=f:read("*line")
            if not line then break end
            local p = smatch(line,"(.*)%.tcz")
            if p then
                DEP[#DEP+1] = p
            elseif line=="" or line==" " then --print("space",line,filename)
            else print("error",line,path_filename)
            end
        end
        f:close()
        return DEP
    end
end

local function readRemote_Ts(url)
    local x, size, ts = bySocket_header(url)
    if not ts then
        return "noTS"
    else
        return ts
    end
end
local function readRemoteMD5(url)
    local t, ts = bySocket_table(url)
    if not t then
        return "noMD5"
    else
        return smatch(t[1], "^(%x+)%s")
    end
end
local function readRemoteDEP(url)
    local t, ts = bySocket_table(url)
    if not t then
        return "noDep"
    else
        local DEP = {}
        for i=1,#t do sgsub(t[i], "([^%s]-)%.tcz", function(p) DEP[#DEP+1]=p end) end
        return DEP
    end
end


local function get_Md5_Dep(item, url, filename, remote)
    if remote then
        item[2] = readRemote_Ts(sformat("%s%s.tcz",         url, filename))
        item[3] = readRemoteMD5(sformat("%s%s.tcz.md5.txt", url, filename))
        item[4] = readRemoteDEP(sformat("%s%s.tcz.dep",     url, filename))
    else
        item[2] = readLocal_Ts(sformat("%s%s.tcz",         url, filename))
        item[3] = readLocalMD5(sformat("%s%s.tcz.md5.txt", url, filename))
        item[4] = readLocalDEP(sformat("%s%s.tcz.dep",     url, filename))
    end
end
local dot = "." --schar(201)
local function genDB(MIRROR)
    progress("Generating new DB.")
    local SL = MIRROR.data
    local url = MIRROR.url
    for filename,tab in pairs(SL) do
        get_Md5_Dep(SL[filename], url, filename, opts.is_ONLINE)
        iwrite(dot)
    end
    iwrite("\n")
    opts.DB = {data=SL, cl=MIRROR.cl, ts=MIRROR.ts}
    opts.is_CHANGED=true
end

local function RegisterNewFilesInTCZ(DBdata,UNREGISTRED)
    for k=1,#UNREGISTRED do
        DBdata[UNREGISTRED[k]].installed=true
    end
    opts.is_CHANGED=true
end
local function DB_check(DBdata)
    local OPT = attrdir(opts.optional)
    -- PKGs marked as 'installed' in DB - do they realy exist in TCZ
    print("\nChecking DB consistention...")
    for pkg in pairs(DBdata) do
        if DBdata[pkg].installed then
            if not OPT[sformat("%s.tcz",pkg)] then print("WARNING: pkg --[ "..pkg.." ]-- was installed but is missing in "..opts.optional) end
        end
    end
    print("\nSearching for unregistred Files in TCZ...")
    local UNREGISTRED = {}
    for filename in pairs(OPT) do
        if DBdata[ssub(filename,0,-5)] then 
            if not DBdata[ssub(filename,0,-5)].installed then UNREGISTRED[#UNREGISTRED+1]=ssub(filename,0,-5) end
        end
    end
    if #UNREGISTRED>0 then
        print("    Found ".. #UNREGISTRED .." UNREGISTRED files in TCZ directory.")
        if opts.isINTERACTIVE then
            if ask("Register now?") then
                RegisterNewFilesInTCZ(DBdata,UNREGISTRED)
            end
        end
    end
end
local function updateTCZ (UPDATES,DBdata,url)
    for n=1,#UPDATES do
        fetch( DBdata, url, UPDATES[n][1] )
    end
end

local function updateDB (DB,MIRROR)
    progress("Updating DB. Please wait...")
    local DBdata, url = DB.data, MIRROR.url
    local NEW = {}
    local CHANGED = {}
    local UPDATES = {}
    for filename,v in pairs(MIRROR.data)do
        local item = DBdata[filename]
        if not item then
            DBdata[filename] = {v[1],0}
            get_Md5_Dep(DBdata[filename], url, filename, true)
            NEW[#NEW+1] = filename
            iwrite(dot)

        elseif item[1] < v[1] then
            if item.installed then
                UPDATES[#UPDATES+1] = {filename,v[1]}
            else
                item[1] = v[1]
                get_Md5_Dep(item, url, filename, true)
                CHANGED[#CHANGED+1] = filename
                iwrite(dot)
            end
        end
    end    
    iwrite(sformat("\n MIRROR was updated - from total %d items - %d new, %d changed.\n Available updates: %d.\n", #NEW+#CHANGED+#UPDATES, #NEW, #CHANGED, #UPDATES))

    for n=1,#UPDATES do
    --                  ! dosbox                                  1.12MB (0/2) (0/5.34)
        iwrite(sformat("! %-40s %6.2fMB  \n", UPDATES[n][1], UPDATES[n][2] / opts.MBdivider))
    end    
    if #UPDATES>0 and ask("\n Do you wish to update your TCZ?") then updateTCZ (UPDATES, DBdata, MIRROR.url) end

    DB.ts = MIRROR.ts
    opts.DB = DB
    opts.is_CHANGED=true
    -- print(serialize(DBdata["dbus"]))
end



-- INSTALLED table contain lists of installed pkgs for many UUID DRIVE
INSTALLED = loadtable ("INSTALLED", "return {}")
function checkInstalled()
    local UUIDs = getUUIDs()
    for uuid,drv in pairs(UUIDs) do
        if INSTALLED[uuid] then
            check()
        end
    end
end


local function getOnlineProfile(url)
    local t = bySocket_table(url)
    return t[1]
end



local function LoadDB()
    local DB = loadtable("db.lua", "return {ts=0}")
    if DB.ts==0 then
        iwrite("DB is empty.\n")
    else
        local pkgs, installed = 0, 0
        for k,v in pairs(DB.data) do
            pkgs=pkgs+1
            if v.installed then installed=installed+1 end
        end
        boxit(sformat("DB has %d pkgs(%d installed) and is %s old.", pkgs, installed, RelativeDate(os.time() - DB.ts)))
    end
    opts.DB = DB
    return DB
end
local function isONLINE()
	if opts.windows then
		if smatch( cmd("ping -n 1 -w 1 8.8.8.8"), "=(%d-) ms") then    -- www.tinycorelinux.com >> google DNS is faster
			opts.is_ONLINE = true
			return true
		else
			print("Currently OFFLINE. Try local MIRROR from ".. opts.localMirror ..".")
		end
	else
		if smatch( cmd("ping -c 1 8.8.8.8"), "time=(.-) ms") then    -- www.tinycorelinux.com >> google DNS is faster
			opts.is_ONLINE = true
			return true
		else
			print("Currently OFFLINE. Try local MIRROR from ".. opts.localMirror ..".")
		end
	
	end
end

local function parse_sizelist()
    local SL, err = {},""
    local function parse (name,size)SL[name]={tonumber(size),0,"md5",{}}end
    if opts.windows then
		require "gzio"
		local gzFile = gzio.open(opts.sizelist, "rb")
		if not gzFile then
			SL, err = false, "gzio.open failed!"
		else
			for line in gzFile:lines() do
				sgsub(line,"([^%s]+)%.tcz%s(%d+)",parse)
			end
			gzFile:close()
		end
		if not SL then
			iwrite("sizelist is corrupted - ",opts.sizelist," ",err,"\n")
			os.exit(4)
		end
	else
		local data = cmd('gzip -dc /media/USB_BOOT/data/_dev/myExt/cache/sizelist.gz')
		sgsub(data,"([^%s]+)%.tcz%s(%d+)",parse)
		if not data then
			iwrite("sizelist is corrupted - ",opts.sizelist,"\n")
			os.exit(4)
		end
    end
    return SL
end
local function LocalMirror(lastupdate)
    local path = opts.localMirror
    local sizelist = path .."sizelist.gz"
    local slt = lfs.attributes(sizelist)
    if not slt then
        iwrite(" LocalMirror is corrupted - missing ",sizelist,"\n")
        os.exit(3)
    end
    return {data=parse_sizelist(sizelist), cl=slt.size, ts=slt.modification, url=path}  -- path=path
end
local function RemoteMirror(lastupdate)     -- getRemoteSizelist(lastupdate)
    -- check CACHE sizelist
    local cache_sizelist = opts.sizelist
    local tmp_sizelist_new = "tmp/sizelist.new"
    local cache_sizelist_attributes = lfs.attributes(cache_sizelist)

    local m = opts.MIRRORS[1]
    -- take HEADER
    m.x, m.cl, m.ts = bySocket_header( sformat("%ssizelist.gz", m[1]) )

    -- check if remote and local cache_sizelist are same
    if cache_sizelist_attributes and cache_sizelist_attributes.size==m.cl and cache_sizelist_attributes.modification==m.ts then
        -- file is same - use cache
        iwrite(" Mirror wasn't changed since then.\n")
        -- m.ts = 0
    else
        -- print(serialize(m))
        iwrite(sformat("Mirror was updated %s ago. Downloading... ", RelativeDate(os.time()-m.ts)))

        m.speed = bySocket_file(sformat("%ssizelist.gz", m[1]), tmp_sizelist_new)

        os.remove(cache_sizelist)
        os.rename(tmp_sizelist_new, cache_sizelist)
        lfs.touch(cache_sizelist, m.ts)

        iwrite(sformat("   %s  @ %s KB/s\n", smatch(m[1],"^(.-://[^/]+/)"), m.speed))
    end

    if not lfs.attributes(cache_sizelist) then
        iwrite(" Sizelist is corrupted - missing ",cache_sizelist,"\n")
        os.exit(3)
    end
    -- print(serialize(m))

    return {data=parse_sizelist(), cl=m.cl, ts=m.ts, url=m[1]}
end
function CheckUpdates( DB )
    local MIRROR                            -- MIRROR.data=nil; print(serialize(MIRROR))
    if isONLINE() then MIRROR = RemoteMirror(DB.ts)
    else               MIRROR =  LocalMirror(DB.ts) end
    opts.MIRROR = MIRROR
    if not DB.data then
        return genDB( MIRROR )
    else
        if DB.ts < MIRROR.ts then
            return updateDB( DB, MIRROR )
        else
            boxit("DB is actual.")
            return DB
        end
    end
end
local function SaveChanges()
    if opts.is_CHANGED then
        savetable2( "db.lua", opts.DB )
        opts.is_CHANGED=false
        boxit("DB was Saved.")
    end
end

-- 
-- name: ListLastApps
-- @param
-- @return

local function ListLastApps(DBdata, day_limit)
    local limit = day_limit or 7
    limit = os.time() - (limit * 86400)
	local T = {}
    for pkg,item in pairs(DBdata) do
        if item[2] > limit then
			T[#T+1] = {item[2], pkg}
        end
    end
    table.sort(T, function(a,b) return a[1]>b[1] end)
    for n=1,#T do
        iwrite(sformat("%-40s %9s old\n", T[n][2], RelativeDate(os.time() - T[n][1])))
    end
end
local function showHelp()
    iwrite([[
    Get Online P)rofile
    C)heck DB consistency
    I)nstall
    O)nDemand
    S)earch <pkg>
    F)etch <pkg>
    U)pdate
    L)ist the newest pkgs [day_limit]   (default day_limit=7)
    R)emove <pkg>
    Q)uit
]]);
end ----------------------------------------------------------------------------

local function Get_user_input()
    iwrite("\n(? for help)",checkRoot());
    io.flush()
    --os.execute("get.exe C >0"); local f=io.input("0"); local user_input = f:read(1) or ""; f:close()
    --return (user_input:lower())
	return string.lower(tostring(io.read()))
end ----------------------------------------------------------------------------



do  -- Main
    CheckUpdates( LoadDB() )

    local DBdata = opts.DB.data

    while true do
        SaveChanges()
        local key = Get_user_input()
        if string.match(key, "^%w- %w") then
            local command, param = string.match(key, "^(%w-) (.*)$")
            if     command=="i" then   OnBoot(DBdata, param)   -- the program is loaded to RAM when the computer is started.
            elseif command=="o" then OnDemand(DBdata, param)   -- programs are not loaded until you start them. When using OnDemand, the computer starts quicker, and uses less RAM than other operating systems.
            elseif command=="s" then   Search(DBdata, param, 2)
            elseif command=="f" then    fetch(DBdata, opts.MIRRORS[1][1], param)
            elseif command=="r" then   Remove(DBdata, param)
            elseif command=="l" then   ListLastApps(DBdata, param)
            elseif command=="ii" then   iinfo(DBdata, param)
            end
        else
            if     key=="u"   then UpdateDB()
            elseif key=="l"   then ListLastApps(DBdata,7)
            elseif key=="c"   then DB_check(DBdata)
            elseif key=="tbm" then takeTheBestMirror()
            elseif key=="p"   then print( "first_online_profile", getOnlineProfile("http://dl.dropbox.com/u/18164947/first_online_profile") )
            elseif key=="h" or key=="help" or key=="?" then showHelp()
            elseif key=="q"   then SaveChanges(); break
            end
        end
    end
end --------------------------------------------------------------------------
