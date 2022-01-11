
local info   = debug.getinfo(1,'S');
script_path  = info.source:match[[^@?(.*[\/])[^\/]-$]]

------------------------------------------------------------------
-- IS PROJECT SAVED
------------------------------------------------------------------

function IsProjectSaved()
  if reaper.GetOS() == "Win32" or reaper.GetOS() == "Win64" then separator = "\\" else separator = "/" end
  retval, project_path_name = reaper.EnumProjects(-1, "")
  if project_path_name ~= "" then
    dir = project_path_name:match("(.*"..separator..")")
    project_saved = true
    return project_saved, dir, separator
  else
    display = reaper.ShowMessageBox("You need to save the project to execute Nabla Looper.", "File Export", 1)
    if display == 1 then
      reaper.Main_OnCommand(40022, 0) -- SAVE AS PROJECT
      return IsProjectSaved()
    end
  end
end

saved, dir, sep = IsProjectSaved()

version = "v.0.3.0"

console = 1
title = 'Nabla Looper A - Start Stop.lua'
local function Msg(value, line)
	if console == 1 then
		reaper.ShowConsoleMsg(tostring(value))
		if line == 0 then
			reaper.ShowConsoleMsg("\n")
		else
			reaper.ShowConsoleMsg("\n-----\n")
		end
	end
end
------------------------------------------------------------------
-- SET ON TOGGLE COMMAND STATE
------------------------------------------------------------------
local _, _, sec, cmd, _, _, _ = reaper.get_action_context()
reaper.SetToggleCommandState( sec, cmd, 1 )
reaper.RefreshToolbar2( sec, cmd )

------------------------------------------------------------------
-- DEFINE VARIABLES AND TABLES
------------------------------------------------------------------
local format    = string.format
local match     = string.match
local gsub      = string.gsub
local gmatch    = string.gmatch
local find      = string.find
local sub       = string.sub
local concat    = table.concat
local insert    = table.insert
local tracks    = {}
local items     = {}
local recTracks = {}
local triggers  = {}
local flags     = {}
local ins       = {}
local out       = {}
local practice  = {}
local storedConfigs = {}
local recItems      = {}
local selected = false -- new notes are selected
------------------------------------------------------------------
-- GET/SET EXT STATES
------------------------------------------------------------------
local function GetSetNablaConfigs()
	local vars = { 
		{'safeMode',    'SAFE_MODE',    'true' }, 
		{'startTime',   'START_TIME',   '1'    }, 
		{'bufferTime',  'BUFFER_TIME',  '1'    },
		{'preservePDC', 'PRESERVE_PDC', 'true' },
		{'practiceMode','PRACTICE_MOD', 'false'},
	}
	for i = 1, #vars do
		local varName = vars[i][1]
		local section = vars[i][2]
		local id      = vars[i][3]
		_G[varName] = reaper.GetExtState( 'NABLA_LOOPER_ARRANGED', section )
		if _G[varName] == "" or _G[varName] == nil then
			reaper.SetExtState( 'NABLA_LOOPER_ARRANGED', section, id, true )
			_G[varName] = id
		end
	end
end

local function GetItemType( item, getsectiontype ) -- MediaItem* item, boolean* getsectiontype
	local take   = reaper.GetActiveTake(item)
	if not take then return false, "UNKNOW" end
	local source = reaper.GetMediaItemTake_Source(take)
	local type   = reaper.GetMediaSourceType(source, "")
	-- Return: boolean isSection, if getsectiontype then return string SECTION TYPE, if not then return "SECTION".
	if type ~= "SECTION" then
		return false, type
	else
		if not getsectiontype then
			return true, type
		else
			local r, chunk     = reaper.GetItemStateChunk(item, "", false)
			for type in  gmatch(chunk, '<SOURCE%s+(.-)[\r]-[%\n]') do
				if type ~= "SECTION" then
					return true, type
				end
			end
		end
	end
end

local function GetItemAction(cItem)
	local r, action     = reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_ACTION', '', false)
	if r then 
		return action 
	else
		old_action = ""
		local r, isRec      = reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECORDING', '', false)
		local r, isRecMute  = reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECMUTE', '', false)
		local r, isMon      = reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_MON', '', false)
		if isRec     == "1" then 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_ACTION', '1', true) 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECORDING', '', true)
			old_action = "1"
		else 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECORDING', '', true) 
		end
		if isRecMute == "1" then 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_ACTION', '2', true) 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECMUTE', '', true) 
			old_action = "2"
		else 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_RECMUTE', '', true) 
		end
		if isMon     == "1" then 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_ACTION', '3', true) 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_MON', '', true) 
			old_action = "3"
		else 
			reaper.GetSetMediaItemInfo_String(cItem, 'P_EXT:ITEM_MON', '', true) 
		end
		return old_action
	end
end

------------------------------------------------------------------
-- TABLA ALL ITEMS
------------------------------------------------------------------
local function CreateTableAllItems()
	local count = reaper.CountMediaItems(proj)
	for i = 0, count - 1 do
		local cItem           = reaper.GetMediaItem(proj, i)
		local section, type   = GetItemType( cItem, true )
		if type ~= "UNKNOW" and type ~= "RPP_PROJECT" and type ~= "VIDEO" and type ~= "CLICK" and type ~= "LTC" and type ~= "VIDEOEFFECT" then
			local iPos          = tonumber(format("%.3f", reaper.GetMediaItemInfo_Value(cItem,"D_POSITION")))
			local siPos         = "i"..gsub(tostring(iPos), "%.+","")
			local iLen          = reaper.GetMediaItemInfo_Value(cItem,"D_LENGTH")
			local iEnd          = tonumber(format("%.3f", iPos+iLen))
			local siEnd         = "o"..gsub(tostring(iEnd), "%.+","")
			local action        = GetItemAction(cItem)
			local cTake         = reaper.GetActiveTake( cItem )
			local name          = reaper.GetTakeName( cTake )
			local subTkName     = match(name, '(.-)%sTK:%d+$')
			local tkName        = subTkName or name
			local sTkName       = tkName:gsub("%s+", "")
			local tkIdx         = match(tkName, '%d+$')
			local cTrack        = reaper.GetMediaItem_Track( cItem )
			local trRecInput    = reaper.GetMediaTrackInfo_Value(cTrack, 'I_RECINPUT')
			local trRecMode     = reaper.GetMediaTrackInfo_Value( cTrack, 'I_RECMODE' )
			local itemLock      = reaper.GetMediaItemInfo_Value( cItem, 'C_LOCK')
			local source 				= reaper.GetMediaItemTake_Source(cTake)
			local _, _, _, mode = reaper.PCM_Source_GetSectionInfo( source )
			items[#items+1] = {
				cItem        = cItem, 
				iPos         = iPos, 
				iEnd         = iEnd, 
				siPos        = siPos, 
				siEnd        = siEnd,
				action       = action,
				iLen         = iLen, 
				cTake        = cTake, 
				tkName       = tkName, 
				tkIdx        = tkIdx,
				cTrack       = cTrack,
				trRecInput   = trRecInput, 
				sTkName      = sTkName, 
				buffer       = 0,
				record       = 0,
				mode         = mode,
				trRecMode    = trRecMode,
				type         = type,
				itemLock     = itemLock,
				section      = section,
				source       = source,
			}
		end
	end
	table.sort(items, function(a,b) return a.iPos < b.iPos end) 
end

------------------------------------------------------------------
-- SET BUFFER, CREATE TABLE TRIGGERS, SET RECORD TRACK CONFIGS
------------------------------------------------------------------

local function AddToRecordingItemsTable(i, v)
	recItems[#recItems+1] = {idx = i, iPos = v.iPos, iEnd = v.iEnd}
end

local function SetIfBuffer(m, v)
	if v.tkName == m.tkName then
		if m.iPos >= v.iEnd-0.1 and m.iPos <= v.iEnd+0.1 then
			v.buffer = 1
		end
	end
end

local function AddToGroupItemsByNameTable(v)
	flags[v.sTkName] = true
	_G[ v.sTkName ] = {}
	for j = 1, #items do
		local m = items[j]
		if v.tkName == m.tkName then
			_G[ v.sTkName ][ #_G[ v.sTkName ] + 1 ] = {idx = j }
		end
	end
end

local function AddToInsTable(v)
	_G[ v.siPos ] = {}
	for j = 1, #ins do
		local m = items[j]
		if m.action ~= "0" and m.action ~= "" then
			if  v.iPos == m.iPos then
				_G[ v.siPos ][ #_G[ v.siPos ] + 1 ] = { idx = j }
			end
		end
	end
end

local function AddToOutTable(v)
	_G[ v.siEnd ] = {}
	for j = 1, #items do
		local m = items[j]
		if m.action ~= "0" and m.action ~= "" then
			if  v.iEnd == m.iEnd then
				_G[ v.siEnd ][ #_G[ v.siEnd ] + 1 ] = { idx = j }
			end
		end
	end
end

local function AddToActionTimesTable(i, v)
	if not flags["sta"..v.iPos] then
		flags["sta"..v.iPos] = true
		ins[ #ins + 1 ]  = {idx = i, siPos = v.siPos, iPos = v.iPos } 
		-- AddToInsTable(v)
	end
	if not flags["end"..v.iEnd] then
		flags["end"..v.iEnd] = true
		out[ #out + 1 ] = {idx = i, siEnd = v.siEnd, iEnd = v.iEnd }
		-- AddToOutTable(v)
	end
end

local function AddToActionTracksTable(v)
	if not flags[v.cTrack] then
		flags[v.cTrack] = true
		recTracks[ #recTracks + 1 ] = { cTrack = v.cTrack, trRecInput = v.trRecInput, trRecMode = v.trRecMode, action = v.action}
	end
end

local function MainTables()
	for i = 1, #items do
		local v = items[i]
		if tonumber(v.action) > 0 then 
			if v.action ~= "3" then AddToRecordingItemsTable(i, v) end
			AddToActionTracksTable(v)
			AddToActionTimesTable(i, v)
			for j = 1, #items do
				local m = items[j]
				SetIfBuffer(m, v)
				if not flags[v.sTkName] then AddToGroupItemsByNameTable(v, m, j) end
			end
		end
	end
	table.sort(ins, function(a,b) return a.iPos < b.iPos end) 
	table.sort(out, function(a,b) return a.iEnd < b.iEnd end) 
	table.sort(recItems, function(a,b) return a.iPos < b.iPos end)
	-------------------------
	for i = 1, #ins do
		local iPos  = ins[i].iPos
		local siPos = ins[i].siPos
		-- reaper.ShowConsoleMsg(v.."\n")
		_G[ siPos ] = {}
		for j = 1, #items do
			if items[j].action ~= "0" and items[j].action ~= "" then
				if iPos == items[j].iPos then
					-- reaper.ShowConsoleMsg("Tabla ins: "..v.." "..j.."\n")
					_G[ siPos ][ #_G[ siPos ] + 1 ] = { idx = j }
				end
			end
		end
	end

	-- Debug Start Tables
	for i = 1, #ins do
		local siPos = ins[i].siPos
		Msg( "At start position: "..ins[i].iPos, 0 )
		for j = 1, #_G[ siPos ] do
			local index = items[ _G[siPos][j].idx ]
			Msg( "--> Arm: "..index.tkName, 0 )
		end
	end
	-------------------------
	-------------------------
	for i = 1, #out do
		local iEnd  = out[i].iEnd
		local siEnd = out[i].siEnd
		-- reaper.ShowConsoleMsg(v.."\n")
		_G[ siEnd ] = {}
		for j = 1, #items do
			if items[j].action ~= "0" and items[j].action ~= "" then
				if iEnd == items[j].iEnd then
					_G[ siEnd ][ #_G[ siEnd ] + 1 ] = { idx = j }
				end
			end
		end
	end
	-- Debug Out Tables
	for i = 1, #out do
		local siEnd = out[i].siEnd
		Msg( "At end position: "..out[i].iEnd, 0 )
		for j = 1, #_G[ siEnd ] do
			local index = items[ _G[siEnd][j].idx ]
			Msg( "--> Unarm: "..index.tkName, 0 )
		end
	end
	---------------------------
end

local function SetActionTracksConfig()
	for i = 1, #recTracks do
		local v = recTracks[i]
		if v.action == "1" then
			if v.trRecMode >= 7 and v.trRecMode <= 9 or v.trRecMode == 16 then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 0 )
			end	
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_FREEMODE', 0 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMONITEMS', 1 )
			reaper.SetMediaTrackInfo_Value( v.cTrack , 'I_RECMON', 0 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECARM', 0 )
		elseif v.action == '2' then
			if v.trRecMode ~= 0 then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 0 )
			end	
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_FREEMODE', 0 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMONITEMS', 1 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECARM', 0 )
		end
		if v.action == "3" then
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 2 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECARM', 1 )
		end
	end
end

----------------------------------------------------------------
-- SET/RESTORE REAPER DAW CONFIGS
------------------------------------------------------------------
local function SetReaperConfigs()
	local tActions = {
		-- { action = 40036, setstate = "on" }, -- View: Toggle auto-view-scroll during playback
		-- { action = 41817, setstate = "on" }, -- View: Continuous scrolling during playback
		{ action = 41078, setstate = "off" }, -- FX: Auto-float new FX windows
		{ action = 40041, setstate = "off"}, -- Options: Toggle auto-crossfades
		{ action = 41117, setstate = "off"}, -- Options: Toggle trim behind items when editing
		{ action = 41330, setstate = "__" }, -- Options: New recording splits existing items and creates new takes (default)
		{ action = 41186, setstate = "__" }, -- Options: New recording trims existing items behind new recording (tape mode)
		{ action = 41329, setstate = "on" }, -- Options: New recording creates new media items in separate lanes (layers)
	}
	for i = 1, #tActions do
		local v = tActions[i]
		-- retval, buf = reaper.get_config_var_string( 'trimmidionsplit' )
		-- reaper.ShowConsoleMsg(tostring(buf).."\n")
		local state = reaper.GetToggleCommandState( v.action )
		storedConfigs[i] = { action = v.action, state = state }
		if     state == 1 and v.setstate == 'off' then
			reaper.Main_OnCommand(v.action, 0)
		elseif state == 0 and v.setstate == "on" then
			reaper.Main_OnCommand(v.action, 0)
		end
	end
end

local function RestoreConfigs()
	for i = 1, #storedConfigs do
		local v = storedConfigs[i]
		local state = reaper.GetToggleCommandState( v.action )
		if v.state ~= state then
			reaper.Main_OnCommand(v.action, 0)
		end
	end
end

local function GetIDByScriptName(scriptName)
	if type(scriptName)~="string"then 
		error("expects a 'string', got "..type(scriptName),2) 
	end
	local file = io.open(reaper.GetResourcePath()..'/reaper-kb.ini','r'); 
	if not file then 
		return -1 
	end
	local scrName = gsub(gsub(scriptName, 'Script:%s+',''), "[%%%[%]%(%)%*%+%-%.%?%^%$]",function(s)return"%"..s;end);
	for var in file:lines() do;
		if match(var, scrName) then
			local id = "_" .. gsub(gsub(match(var, ".-%s+.-%s+.-%s+(.-)%s"),'"',""), "'","")
			return id
		else
		end
	end
	return -1
end

-- Modified from X-Raym's action: Insert CC linear ramp events between selected ones if consecutive
local function GetCC(take, cc)
	return cc.selected, cc.muted, cc.ppqpos, cc.chanmsg, cc.chan, cc.msg2, cc.msg3
end

local function ExportMidiFile(take_name, take, sTkName, newidx, strToStore) -- local (i, j, item, take, track)
	if dir == "" then return end
	local src = reaper.GetMediaItemTake_Source(take)
	-- interpolate CC points
	local retval, notes, ccs, sysex = reaper.MIDI_CountEvts(take)
	if ccs > 0 then
		-- Store CC by types
		local midi_cc = {}
		for j = 0, ccs - 1 do
			local cc = {}
			retval, cc.selected, cc.muted, cc.ppqpos, cc.chanmsg, cc.chan, cc.msg2, cc.msg3 = reaper.MIDI_GetCC(take, j)
			if not midi_cc[cc.msg2] then midi_cc[cc.msg2] = {} end
			table.insert(midi_cc[cc.msg2], cc)
		end
		-- Look for consecutive CC
		local cc_events = {}
		local cc_events_len = 0
		for key, val in pairs(midi_cc) do
			-- GET SELECTED NOTES (from 0 index)
			for k = 1, #val - 1 do
				a_selected, a_muted, a_ppqpos, a_chanmsg, a_chan, a_msg2, a_msg3 = GetCC(take, val[k])
				b_selected, b_muted, b_ppqpos, b_chanmsg, b_chan, b_msg2, b_msg3 = GetCC(take, val[k+1])
				-- INSERT NEW CCs
				local interval = (b_ppqpos - a_ppqpos) / 32  -- CHANGED FROM ORIGINAL, so it just puts points every 32 ppq
				local time_interval = (b_ppqpos - a_ppqpos) / interval
				for z = 1, interval - 1 do
					local cc_events_len = cc_events_len + 1
					cc_events[cc_events_len] = {}
					local c_ppqpos = a_ppqpos + time_interval * z
					local c_msg3 = math.floor( ( (b_msg3 - a_msg3) / interval * z + a_msg3 )+ 0.5 )
					cc_events[cc_events_len].ppqpos = c_ppqpos
					cc_events[cc_events_len].chanmsg = a_chanmsg
					cc_events[cc_events_len].chan = a_chan
					cc_events[cc_events_len].msg2 = a_msg2
					cc_events[cc_events_len].msg3 = c_msg3
				end
			end
		end
		-- Insert Events
		for i, cc in ipairs(cc_events) do
			reaper.MIDI_InsertCC(take, selected, false, cc.ppqpos, cc.chanmsg, cc.chan, cc.msg2, cc.msg3)
		end
	end

	local audio = { "midi"..sep, "MIDI"..sep, "Midi"..sep, "Audio"..sep, "audio"..sep, "AUDIO"..sep, "Media"..sep, "media"..sep, "MEDIA"..sep, ""}
	for i = 1, #audio do
		local fn = dir..audio[i]..take_name..".mid"
		retval = reaper.CF_ExportMediaSource(src, fn)
		if retval == true then 
			if practiceMode == 'false' then
				reaper.SetProjExtState(proj, sTkName, newidx, fn..strToStore) 
				break 
			else
				practice[#practice+1] = fn
				break 
			end
		end
	end
	reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(reaper.GetMediaItemTake_Item(take)), reaper.GetMediaItemTake_Item(take) )
end

local function SetFXName(track, fx, new_name)
	if not new_name then return end
	local edited_line,edited_line_id, segm
	-- get ref guid
	if not track or not tonumber(fx) then return end
	local FX_GUID = reaper.TrackFX_GetFXGUID( track, fx )
	if not FX_GUID then return else FX_GUID = sub(gsub(FX_GUID,'-',''), 2,-2) end
	local plug_type = reaper.TrackFX_GetIOSize( track, fx )
	-- get chunk t
	local retval, chunk = reaper.GetTrackStateChunk( track, '', false )
	local t = {} for line in gmatch(chunk, "[^\r\n]+") do t[#t+1] = line end
	-- find edit line
	local search
	for i = #t, 1, -1 do
		local t_check = gsub(t[i], '-','')
		if find(t_check, FX_GUID) then search = true  end
		if find(t[i], '<') and search and not find(t[i],'JS_SER') then
			edited_line = sub(t[i], 2)
			edited_line_id = i
			break
		end
	end
	-- parse line
	if not edited_line then return end
	local t1 = {}
	for word in gmatch(edited_line,'[%S]+') do t1[#t1+1] = word end
	local t2 = {}
	for i = 1, #t1 do
		segm = t1[i]
		if not q then t2[#t2+1] = segm else t2[#t2] = t2[#t2]..' '..segm end
		if find(segm,'"') and not find(segm,'""') then if not q then q = true else q = nil end end
	end
	if plug_type == 2 then t2[3] = '"'..new_name..'"' end -- if JS
	if plug_type == 3 then t2[5] = '"'..new_name..'"' end -- if VST
	local out_line = concat(t2,' ')
	t[edited_line_id] = '<'..out_line
	local out_chunk = concat(t,'\n')
	--msg(out_chunk)
	reaper.SetTrackStateChunk( track, out_chunk, false )
end

local function InsertReaDelay()
	reaper.Undo_BeginBlock()
	local tStrRec = {}
	for i = 1, #recTracks do
		local v = recTracks[i]
		if v.action ~= '3' then
			if v.trRecInput < 4096 then
				local isFx = reaper.TrackFX_AddByName( v.cTrack, 'ReaDelay', false, -1000 )
				reaper.TrackFX_SetParam( v.cTrack, isFx, 0, 1 )
				reaper.TrackFX_SetParam( v.cTrack, isFx, 1, 0 )
				reaper.TrackFX_SetParam( v.cTrack, isFx, 13, 0 )
				SetFXName(v.cTrack, isFx, 'Nabla ReaDelay')
			end
		end
	end
	reaper.Undo_EndBlock("Insert Nabla ReaDelay", -1)
end

local function SetPDC( set )
	reaper.Undo_BeginBlock()
	local tStrRec = {}
	for i = 1, #recTracks do
		local v = recTracks[i]
		if v.action ~= '3' then
			local r, trChunk = reaper.GetTrackStateChunk(v.cTrack, '', false)
			local strRec = match(trChunk, 'REC%s+.-[%\n]')
			for substring in gmatch(strRec, "%S+") do insert(tStrRec, substring) end

			local function set_pdc( str )
				local new_strRec = gsub(trChunk, 'REC%s+.-[%\n]', str, 1)
				reaper.SetTrackStateChunk(v.cTrack, new_strRec, true)
				for j = 1, #tStrRec do tStrRec[j] = nil end
			end

			if set == 'true' then
				tStrRec[7] = "1"
				local new_strRec = concat(tStrRec, " ")
				set_pdc( new_strRec )
			else
				tStrRec[7] = "0"
				local new_strRec = concat(tStrRec, " ")
				set_pdc( new_strRec )
			end
		end
	end
	reaper.Undo_EndBlock("--> START ARRANGED MODE", -1)
end

local function RemoveReaDelay()
	for i = 1, #recTracks do
		local v = recTracks[i]
		if v.trRecInput < 4096 then
			reaper.TrackFX_Delete( v.cTrack, reaper.TrackFX_AddByName( v.cTrack, 'Nabla ReaDelay', false, 0 ) )
		end
	end
end

local function GetNumForLoopTakes( cTake )
	local newKey = 0
	for i = 0, 500 do
		local retval, key, val = reaper.EnumProjExtState( 0, cTake, i )
		if retval == false then return tonumber(newKey) + 1 end
		newKey = key
	end
end

local function AtExitActions()
	reaper.Undo_BeginBlock()
	reaper.OnStopButton()
	reaper.Main_OnCommand(40345, 0) -- Send all notes off to all MIDI outputs/plug-ins
	local is_new_value, fiLename, sec, cmd, mode, resolution, val = reaper.get_action_context()
	reaper.SetToggleCommandState( sec, cmd, 0 )
	reaper.RefreshToolbar2( sec, cmd )
	for i = 1, #recTracks do
		local v = recTracks[i]
		if v.trRecMode ~= 2 then
			reaper.SetMediaTrackInfo_Value( v.cTrack , 'I_RECMON', 1 )
			reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', v.trRecMode )
			reaper.SetMediaTrackInfo_Value( v.cTrack,  'I_RECARM', 0 )
		end
	end
	if practiceMode == "true" then
		for j = 1, #practice do
			os.remove(practice[j])
		end
		reaper.Undo_BeginBlock()
		local scriptName = "Script: Nabla Looper Arranged Items (Clear).lua"
		local idbyscript = GetIDByScriptName(scriptName)
		reaper.Main_OnCommand(reaper.NamedCommandLookup(idbyscript),0)
		reaper.Undo_EndBlock("--> END ARRANGED MODE", -1)
	end
	if safeMode == "true" then RemoveReaDelay() end
	RestoreConfigs()
	reaper.Undo_EndBlock("--> END ARRANGED MODE", -1)
end

local function errorHandler(errObject)
	reaper.OnStopButton()
	local byLine = "([^\r\n]*)\r?\n?"
	local trimPath = "[\\/]([^\\/]-:%d+:.+)$"
	local err = errObject   and string.match(errObject, trimPath)
	or  "Couldn't get error message."
	local trace = debug.traceback()
	local stack = {}
	for line in string.gmatch(trace, byLine) do
		local str = string.match(line, trimPath) or line
		stack[#stack + 1] = str
	end
	table.remove(stack, 1)
	reaper.ShowConsoleMsg(
	"Error: "..err.."\n\n"..
	"Stack traceback:\n\t"..table.concat(stack, "\n\t", 2).."\n\n"..
	"Nabla:      \t".. version .."\n"..
	"Reaper:      \t"..reaper.GetAppversion().."\n"..
	"Platform:    \t"..reaper.GetOS()
	)
end

local function SetReaDelayTime(cTrack, iLen, trRecInput)
	reaper.TrackFX_SetParam( cTrack, reaper.TrackFX_AddByName( cTrack, 'Nabla ReaDelay', false, 0 ), 4, (reaper.TimeMap_timeToQN_abs( 0, iLen )*2)/256 )
end

local function OnReaDelay(cTrack)
	reaper.TrackFX_SetParam( cTrack, reaper.TrackFX_AddByName( cTrack, 'Nabla ReaDelay', false, 0 ), 13, 1 )
end

local function OffReaDelayDefer(siEnd, redItemEnd)
	xpcall( function()
		if siEnd then
			newsiEnd = siEnd
			sredItemEnd = redItemEnd
		end
		if reaper.GetPlayPosition() > sredItemEnd then
			for i = 1, #_G[ newsiEnd ] do
				reaper.Undo_BeginBlock()
				local v = items[ _G[newsiEnd][i].idx ]
				if v.buffer == 1 then
					reaper.TrackFX_SetParam( v.cTrack, reaper.TrackFX_AddByName( v.cTrack, 'Nabla ReaDelay', false, 0 ), 13, 0 )
				end
				reaper.Undo_EndBlock("End Buffer: " .. v.tkName, -1)
			end
			return
		end
		if reaper.GetPlayState() == 0 then return else reaper.defer(OffReaDelayDefer) end
	end, errorHandler)
end

local function SetItemReverseMode(v)
	reaper.SelectAllMediaItems(proj, false)
	reaper.SetMediaItemSelected(v.cItem, true)
	reaper.Main_OnCommand(41051, 0) -- Item properties: Toggle take reverse
	reaper.SetMediaItemTakeInfo_Value( v.cTake, 'D_STARTOFFS', 0 )
end

local function CreateNewSourceForItem(v, section, tkName, tkIdx)
	local pcm_section = reaper.PCM_Source_CreateFromType("SECTION")
	reaper.SetMediaItemTake_Source(v.cTake, pcm_section)
	local r, chunk = reaper.GetItemStateChunk(v.cItem, "", false) 
	local new_chunk   = gsub(chunk, '<SOURCE%s+.->', section .. "\n>" )
	reaper.SetItemStateChunk(v.cItem, new_chunk, true) 
	reaper.GetSetMediaItemTakeInfo_String( v.cTake, 'P_NAME', tkName.." TK:"..tkIdx, true )
end

local function PropagateAudio(sTkName, section, tkName, tkIdx)
	for i = 1, #_G[sTkName] do
		local v = items[ _G[sTkName][i].idx ]
		if v.itemLock ~= 1 then
			CreateNewSourceForItem(v, section, tkName, tkIdx)
			if v.mode then SetItemReverseMode(v) end
			if v.source then reaper.PCM_Source_Destroy(v.source) end
		end
	end
	reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
end

local function PropagateMIDI(sTkName, section, newidx)
	for i = 1, #_G[sTkName] do
		local v = items[ _G[sTkName][i].idx ]
		local pcm_section = reaper.PCM_Source_CreateFromType("MIDI")
		reaper.SetMediaItemTake_Source(v.cTake, pcm_section)
		local r, chunk = reaper.GetItemStateChunk(v.cItem, "", false) 
		local new_chunk   = gsub(chunk, '<SOURCE%s+.->', section .. "\n>" )
		reaper.SetItemStateChunk( v.cItem, new_chunk, true)
		reaper.GetSetMediaItemTakeInfo_String(v.cTake, 'P_NAME', v.tkName.." TK:"..format("%d", newidx), true )
		if v.source then reaper.PCM_Source_Destroy(v.source) end
	end
end

local function WaitForEnd()
	if reaper.GetPlayState() == 0 then return else reaper.defer(WaitForEnd) end
end

local function ArmTracksByGroupTimes( siPos )
	for i = 1, #_G[ siPos ] do
		reaper.Undo_BeginBlock()
		local v = items[ _G[siPos][i].idx ]
		reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECARM', 1 )
		if safeMode == 'true' then SetReaDelayTime( v.cTrack, v.iLen, v.trRecInput) end
		reaper.Undo_EndBlock("Recording: "..v.tkName, -1)
	end
end

local function ActivateRecording()
	xpcall( function()
		if idxStart == nil or idxStart > #ins then return else
			local iPos  = ins[idxStart].iPos
			local siPos = ins[idxStart].siPos
			if reaper.GetPlayPosition() >= iPos - startTime then 
				if not flags[siPos.."ipos"] then
					flags[siPos.."ipos"] = true
					idxStart = idxStart + 1
					ArmTracksByGroupTimes( siPos )
				end
			end
		end
		if reaper.GetPlayState() == 0 then return else reaper.defer(ActivateRecording) end
	end, errorHandler)
end

local function ArmTrackMonitorGroupMIDI(siPos)
	for i = 1, #_G[ siPos ] do
		local v = items[ _G[siPos][i].idx ]
		 if v.trRecInput >= 4096 then
			reaper.Undo_BeginBlock()
			if v.action == "1" or v.action == "3" then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 1 )
			elseif v.action == "2" then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_MUTE', 1 )
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 1 )
			end
			reaper.Undo_EndBlock("On Monitor: "..v.tkName, -1)
		 end
	end
end

local function ArmTrackMonitorGroupAudio(siPos)
	for i = 1, #_G[ siPos ] do
		local v = items[ _G[siPos][i].idx ]
		if v.trRecInput < 4096 then
			reaper.Undo_BeginBlock()
			if v.action == "1" or v.action == "3" then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 1 )
			elseif v.action == "2" then
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_MUTE', 1 )
				reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 1 )
			end
			reaper.Undo_EndBlock("On Monitor: "..v.tkName, -1)
		end
	end
end

local function ActivateMonitorMIDI()
	xpcall( function()
		if idxStartMonMIDI == nil or idxStartMonMIDI > #ins then return end
		local iPos  = ins[idxStartMonMIDI].iPos
		if reaper.GetPlayPosition() >= iPos - 0.1 then -- For MIDI Tracks
			local siPos = ins[idxStartMonMIDI].siPos
			if not flags["monMIDI"..siPos] then
				flags["monMIDI"..siPos] = true 
				idxStartMonMIDI = idxStartMonMIDI + 1
				ArmTrackMonitorGroupMIDI(siPos)
			end
		end
		if reaper.GetPlayState() == 0 then return else reaper.defer(ActivateMonitorMIDI) end
	end, errorHandler)
end

local function ActivateMonitorAUDIO()
	xpcall( function()
		if idxStartMonAUDIO == nil or idxStartMonAUDIO > #ins then return end
		local iPos  = ins[idxStartMonAUDIO].iPos
		local siPos = ins[idxStartMonAUDIO].siPos
		if reaper.GetPlayPosition() >= iPos - 0.02 then -- For AUDIO Tracks
			if not flags["monAUDIO"..siPos] then 
				flags["monAUDIO"..siPos] = true
				idxStartMonAUDIO = idxStartMonAUDIO + 1
				ArmTrackMonitorGroupAudio(siPos)
			end
		end
		if reaper.GetPlayState() == 0 then return else reaper.defer(ActivateMonitorAUDIO) end
	end, errorHandler)
end

local function DeactivateRecording()
	xpcall( function()
		local pPos = reaper.GetPlayPosition()
		if idxEnd == nil or idxEnd > #out then return end
		local iEnd  = out[idxEnd].iEnd
		------------------------------------------------------------------
		if pPos >= iEnd-0.01 then 
			local siEnd = out[idxEnd].siEnd
			if not flags[siEnd.."endRec"] then flags[siEnd.."endRec"] = true
				idxEnd = idxEnd + 1
				for i = 1, #_G[ siEnd ] do
					reaper.Undo_BeginBlock()
					local v = items[ _G[siEnd][i].idx ]
					------------------------------------------------------------------
					-- UNARM TRACKS
					------------------------------------------------------------------
					if v.action == "1" or v.action == "2" then
						reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECARM', 0 )
						------------------------------------------------------------------
						-- Work with new loop
						------------------------------------------------------------------
						reaper.SelectAllMediaItems( 0, false )
						reaper.Main_OnCommand(40670, 0) -- Record: Add recorded media to project
						local addedItem = reaper.GetSelectedMediaItem(0, 0)
						-- IF ADDED ITEM ----------------------------------------------------------------
						if addedItem then
							if v.trRecInput < 4096 then -- For Audio Item
								reaper.PreventUIRefresh(1)
								reaper.ApplyNudge( 0, 1, 1, 1, v.iPos, 0, 0 ) -- start
								reaper.ApplyNudge( 0, 1, 3, 1, v.iEnd, 0, 0 ) -- end
								local newTake     = reaper.GetActiveTake(addedItem)
								local addedSoffs  = reaper.GetMediaItemTakeInfo_Value( newTake, 'D_STARTOFFS')
								local addedSource = reaper.GetMediaItemTake_Source( newTake )
								local filename    = reaper.GetMediaSourceFileName( addedSource, '' )
								reaper.Main_OnCommand(40547, 0) -- Item properties: Loop section of audio item source
								local r, chunk    = reaper.GetItemStateChunk(addedItem, "", false)
								local section     = match(chunk, '<SOURCE%s+.->')
								reaper.DeleteTrackMediaItem( v.cTrack, addedItem )
								reaper.PreventUIRefresh(-1)
								PropagateAudio(v.sTkName, section, v.tkName, GetNumForLoopTakes( v.sTkName ))
								if practiceMode == 'false' then
									local strToStore = filename..","..addedSoffs..","..v.iLen..",AUDIO,"..v.tkName.." TK:"..GetNumForLoopTakes( v.sTkName) .. ",_"
									reaper.SetProjExtState(proj, v.sTkName, format("%03d",GetNumForLoopTakes( v.sTkName )), strToStore)
								else
									practice[#practice+1] = filename
								end
							else -- For Midi Item     
								reaper.PreventUIRefresh(1)
								reaper.SetMediaItemInfo_Value( addedItem, 'B_LOOPSRC', 0) 
								reaper.SplitMediaItem( addedItem, v.iPos )
								reaper.DeleteTrackMediaItem( v.cTrack, addedItem )
								local addedItem = reaper.GetSelectedMediaItem(0, 0)
								reaper.SplitMediaItem( addedItem, v.iEnd )
								local delSplitItem = reaper.GetSelectedMediaItem(0, 1)
								if delSplitItem then
									reaper.DeleteTrackMediaItem( v.cTrack, delSplitItem ) 
								end
								reaper.SetMediaItemInfo_Value( addedItem, 'B_LOOPSRC', 1)
								reaper.SetMediaItemSelected(addedItem, true)
								local cTake  = reaper.GetActiveTake(addedItem)
								local newidx = format("%03d",GetNumForLoopTakes( v.sTkName ))
								local r, chunk    = reaper.GetItemStateChunk(addedItem, "", false)
								local section     = match(chunk, '<SOURCE%s+.->')
								PropagateMIDI( v.sTkName, section, newidx ) 
								reaper.GetSetMediaItemTakeInfo_String( cTake, 'P_NAME', v.sTkName.." "..newidx, true )
								local strToStore = ",_,"..v.iLen..",MIDI,"..v.tkName.." TK:"..GetNumForLoopTakes( v.sTkName ) .. ",_"
								ExportMidiFile(v.sTkName.." "..newidx, cTake, v.sTkName, newidx, strToStore )
								reaper.PreventUIRefresh(-1)
							end
						end
						reaper.Undo_EndBlock("Propagate: "..v.tkName .. " TK:" .. GetNumForLoopTakes( v.sTkName ), -1)
					end
					------------------------------------------------------------------
				end
			end
		end
		------------------------------------------------------------------
		if reaper.GetPlayState() == 0 then return else reaper.defer(DeactivateRecording) end
	end, errorHandler) 
end

local function DeactivateMonitor()
	xpcall( function()
		local pPos = reaper.GetPlayPosition()
		if idxEndMon == nil or idxEndMon > #out then return end
		local iEnd  = out[idxEndMon].iEnd
		------------------------------------------------------------------
		if pPos >= iEnd-0.1 then 
			local siEnd = out[idxEndMon].siEnd
			if not flags[siEnd.."endMon"] then
				flags[siEnd.."endMon"] = true
				idxEndMon = idxEndMon + 1
				for i = 1, #_G[ siEnd ] do
					reaper.Undo_BeginBlock()
					local v = items[ _G[siEnd][i].idx ]
					if safeMode == 'true' then
						if v.buffer == 1 then
							if v.action == "1" then
								if v.trRecInput < 4096 then
									reaper.TrackFX_SetParam( v.cTrack, reaper.TrackFX_AddByName( v.cTrack, 'Nabla ReaDelay', false, 0 ), 13, 1 )
								end
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
								OffReaDelayDefer( v.siEnd, v.iEnd + bufferTime, v.cTrack )
							elseif v.action == "2" then
								if v.trRecInput < 4096 then
									reaper.TrackFX_SetParam( v.cTrack, reaper.TrackFX_AddByName( v.cTrack, 'Nabla ReaDelay', false, 0 ), 13, 1 )
								end
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_MUTE', 0 )
								OffReaDelayDefer( v.siEnd, v.iEnd + bufferTime, v.cTrack )
							elseif v.action == "3" then
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 2 )
							end
						else
							if v.action == "1" or v.action == "2" then
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
							elseif v.action == "3" then
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
								reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 2 )
							end
						end
					else
						if v.action == "1" then
							reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
						elseif v.action == "2" then
							reaper.SetMediaTrackInfo_Value( v.cTrack, 'B_MUTE', 0 )
						elseif v.action == "3" then
							reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMON', 0 )
							reaper.SetMediaTrackInfo_Value( v.cTrack, 'I_RECMODE', 2 )
						end
					end
					reaper.Undo_EndBlock("Off Monitor: "..v.tkName, -1)
				end
			end
		end
		------------------------------------------------------------------
		if reaper.GetPlayState() == 0 then return else reaper.defer(DeactivateMonitor) end
	end, errorHandler) 
end

local function Main()
	local pState = reaper.GetPlayState()
	if pState ~= 5 then
		CreateTableAllItems()
		MainTables()
		SetActionTracksConfig()
		GetSetNablaConfigs()
		SetReaperConfigs()
		SetPDC( preservePDC )
		if safeMode == "true" then xpcall( InsertReaDelay, errorHandler) end
		------------------------------------------------------------------
		for i = 1, #ins do
			local iPos  = ins[i].iPos
			if iPos - 0.1 > reaper.GetCursorPosition() then
				idxStart         = i
				idxStartMonMIDI  = i
				idxStartMonAUDIO = i
				break
			end
		end
		------------------------------------------------------------------
		for i = 1, #out do
			local iEnd  = out[i].iEnd
			if iEnd - 0.1 > reaper.GetCursorPosition() then
				idxEnd    = i
				idxEndMon = i
				break
			end
		end
		reaper.Main_OnCommand(40252, 0)
		reaper.CSurf_OnRecord()
		-- Start Defer Functions --
		ActivateRecording()
		ActivateMonitorMIDI()
		ActivateMonitorAUDIO()
		DeactivateMonitor()
		DeactivateRecording()
		WaitForEnd()
	end
end

Main()
reaper.atexit(AtExitActions)