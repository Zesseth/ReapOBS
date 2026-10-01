-- ============================================================
-- ReapOBS – Mock REAPER API
-- Provides a minimal, self-contained REAPER API mock so the
-- ReapOBS scripts can be exercised with standalone Lua.
-- Tracks transport state, tracks, items and markers so tests
-- can assert on the resulting project state.
-- License: GNU GPL v2.0
-- ============================================================

local MockReaper = {}
MockReaper.__index = MockReaper

function MockReaper.new(opts)
  opts = opts or {}
  local self = setmetatable({}, MockReaper)
  self.tracks = {}       -- { {name=..., folderdepth=0, items={}} }
  self.markers = {}      -- { {pos=..., name=...} }
  self.msgbox_log = {}   -- { {title=..., msg=...} }
  self.console = {}      -- { "line", ... }
  self.commands = {}     -- { 1013, 1016, ... }
  self.playstate = opts.playstate or 0
  self.playpos = opts.playpos or 0.0
  self.editcur = opts.editcur or 0.0
  self.resource_path = opts.resource_path or "/tmp/reapobs-test"
  self.action_context = opts.action_context or {0, 0, 32060, 57000}
  self.fail_insert_media = opts.fail_insert_media or false
  return self
end

function MockReaper:api()
  local mock = self
  return {
    GetResourcePath = function() return mock.resource_path end,
    ShowConsoleMsg = function(msg)
      mock.console[#mock.console + 1] = tostring(msg)
    end,
    ShowMessageBox = function(msg, title, type)
      mock.msgbox_log[#mock.msgbox_log + 1] = {title = title, msg = msg}
      return 0
    end,
    GetPlayState = function() return mock.playstate end,
    GetPlayPosition = function() return mock.playpos end,
    GetCursorPosition = function() return mock.editcur end,
    SetEditCurPos = function(pos, moveview, seekplay)
      mock.editcur = pos
    end,
    AddProjectMarker = function(proj, isrgn, pos, rgnend, name, wantidx)
      mock.markers[#mock.markers + 1] = {pos = pos, name = name, isrgn = isrgn}
      return #mock.markers - 1
    end,
    CountProjectMarkers = function(proj, num_markersOut, num_regionsOut)
      local markers, regions = 0, 0
      for _, m in ipairs(mock.markers) do
        if m.isrgn then regions = regions + 1 else markers = markers + 1 end
      end
      return markers + regions, markers, regions
    end,
    EnumProjectMarkers3 = function(proj, idx)
      local m = mock.markers[idx + 1]
      if not m then return 0, false, 0, 0, "" end
      return 1, m.isrgn or false, m.pos, 0, m.name or ""
    end,
    EnumProjectMarkers = function(idx)
      local m = mock.markers[idx + 1]
      if not m then return 0, false, 0, 0, "" end
      return 1, m.isrgn or false, m.pos, 0, m.name or ""
    end,
    APIExists = function(name) return true end,
    CountTracks = function(proj) return #mock.tracks end,
    GetTrack = function(proj, idx)
      return mock.tracks[idx + 1] and (idx + 1) or nil
    end,
    GetTrackName = function(tr)
      local t = mock.tracks[tr]
      if not t then return false, "" end
      return true, t.name
    end,
    InsertTrackAtIndex = function(idx, wantDefaults)
      table.insert(mock.tracks, idx + 1,
        {name = "Track " .. (#mock.tracks + 1), folderdepth = 0, items = {}})
    end,
    GetSetMediaTrackInfo_String = function(tr, parm, val, setval)
      local t = mock.tracks[tr]
      if not t then return false, "" end
      if setval and parm == "P_NAME" then t.name = val end
      return true, t.name
    end,
    SetMediaTrackInfo_Value = function(tr, parm, val)
      local t = mock.tracks[tr]
      if t then t[parm] = val end
      return true
    end,
    GetMediaTrackInfo_Value = function(tr, parm)
      local t = mock.tracks[tr]
      if not t then return 0 end
      if parm == "IP_TRACKNUMBER" then return tr end
      return t[parm] or 0
    end,
    CountTrackMediaItems = function(tr)
      local t = mock.tracks[tr]
      return t and #t.items or 0
    end,
    GetTrackMediaItem = function(tr, idx)
      local t = mock.tracks[tr]
      if not t then return nil end
      local it = t.items[idx + 1]
      if not it then return nil end
      it._track = tr
      it._index = idx
      return it
    end,
    InsertMedia = function(fn, mode)
      if mock.fail_insert_media then return 0 end
      if (mode & 3) == 0 and (mode & 512) ~= 0 then
        local target = (mode >> 16)
        local t = mock.tracks[target + 1]
        if not t then return 0 end
        t.items[#t.items + 1] = {
          path = fn, len = 42.5, position = mock.editcur,
          D_POSITION = mock.editcur, D_LENGTH = 42.5,
        }
        return 1
      end
      return 0
    end,
    SetMediaItemInfo_Value = function(item, parm, val)
      if item and type(item) == "table" then item[parm] = val end
      return true
    end,
    GetMediaItemInfo_Value = function(item, parm)
      if item and type(item) == "table" then return item[parm] or 0 end
      return 0
    end,
    DeleteTrackMediaItem = function(tr, item)
      local t = mock.tracks[tr]
      if t and item and item._index then table.remove(t.items, item._index + 1) end
      return true
    end,
    UpdateItemInProject = function() return true end,
    UpdateArrange = function() end,
    Main_OnCommand = function(cmd, val)
      mock.commands[#mock.commands + 1] = cmd
      if cmd == 1013 then
        mock.playstate = 5
        mock.playpos = mock.editcur
      elseif cmd == 1016 then
        mock.playstate = 1
        mock.playpos = 0
      end
    end,
    SetToggleCommandState = function(section, cmd, state)
      mock.toggle_state = state
    end,
    RefreshToolbar2 = function(section, cmd) end,
    get_action_context = function()
      local c = mock.action_context
      return c[1], c[2], c[3], c[4]
    end,
    time_precise = function() return os.clock() end,
  }
end

return MockReaper
