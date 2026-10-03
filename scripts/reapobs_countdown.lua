-- ============================================================
-- ReapOBS – Countdown Window
-- Displays a configurable countdown before recording starts.
-- Shows a large number that counts down, then a red REC
-- indicator once recording has started. ESC aborts.
-- https://github.com/Zesseth/ReapOBS
-- License: GNU GPL v2.0
-- ============================================================

local Countdown = {}

-- --------------------------------------------------------------
-- Draw a text centered in the gfx window
-- ------------------------------------------------------------
local function draw_centered(g, text, r, gr, b)
  g.set(r, gr, b)
  local w, h = g.measurestr(text)
  g.x = (g.w - w) / 2
  g.y = (g.h - h) / 2
  g.drawstr(text)
end

-- --------------------------------------------------------------
-- Run the countdown.
-- opts:
--   seconds    - countdown duration in seconds (0 = skip)
--   font_size  - font size of the countdown number
--   auto_close - seconds to show REC after recording starts
--   on_start   - called when the countdown reaches zero
--   log        - optional log function
--   reaper     - optional REAPER API override (tests)
--   gfx        - optional gfx API override (tests)
-- Returns true if recording was started immediately (seconds <= 0),
-- false otherwise (countdown is running via defer).
-- ------------------------------------------------------------
function Countdown.run(opts)
  local r = opts.reaper or reaper
  local g = opts.gfx or gfx
  local log = opts.log or function() end

  -- No countdown requested: start immediately, current behavior
  if not opts.seconds or opts.seconds <= 0 then
    opts.on_start()
    return true
  end

  local total = opts.seconds
  local start_time = r.time_precise()
  local started = false
  local rec_start_time = nil

  g.init("ReapOBS", 400, 300, 0)
  g.setfont(1, opts.font_size or 120, "Arial")

  local function loop()
    local char = g.getchar()
    -- ESC (27) aborts; -1 means the window was closed
    if char == 27 or char == -1 then
      if not started then
        log("Countdown aborted by user.")
      end
      g.quit()
      return
    end

    local now = r.time_precise()
    local elapsed = now - start_time

    if not started then
      local remaining = math.ceil(total - elapsed)
      if remaining <= 0 then
        started = true
        rec_start_time = now
        log("Countdown finished – starting recording.")
        opts.on_start()
      else
        draw_centered(g, tostring(remaining), 1, 1, 1)
      end
    end

    if started then
      draw_centered(g, "\u{25CF} REC", 1, 0, 0)
      if opts.auto_close and (now - rec_start_time) >= opts.auto_close then
        g.quit()
        return
      end
    end

    r.defer(loop)
  end

  loop()
  return false
end

return Countdown
