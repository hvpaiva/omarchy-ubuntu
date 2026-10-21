-- Hyprland in Lua, Omarchy 4 layout. Learn how to configure at:
-- https://wiki.hypr.land/Configuring/Start/
--
-- Ubuntu/GDM glue. A session started straight by the display manager (the
-- packaged `Hyprland` entry, no uwsm) never goes through a login shell, so
-- /etc/profile.d/omarchy.sh does not run and the compositor has neither
-- OMARCHY_PATH nor the PATH adjustments from $OMARCHY_PATH/default/bash/env-bootstrap.
-- Without them the shell starts from /usr/share/omarchy/shell (upstream's fallback)
-- while terminals use the dev-link path; omarchy-shell matches the Quickshell
-- instance by that path, so every hotkey fails with "OMARCHY_PATH is not set".
-- Like env-bootstrap, /etc/omarchy.conf always wins, even over an inherited value
-- (a previous reload may have left the fallback set in the compositor process).
-- Under uwsm the values already match and this block only reaffirms them.
local omarchy_path = "/usr/share/omarchy"
do
  local conf = io.open("/etc/omarchy.conf")
  if conf then
    for line in conf:lines() do
      local value = line:match("^%s*export%s+OMARCHY_PATH=%s*['\"]?([^'\"%s]+)")
      if value then
        omarchy_path = value
      end
    end
    conf:close()
  end
end

dofile(omarchy_path .. "/default/hypr/bootstrap.lua")

-- Disable every default Omarchy binding (and define your own in hypr/bindings.lua):
-- omarchy_default_bindings = false
--
-- Or disable only the bindings for preinstalled apps and web apps, keeping the WM ones:
-- omarchy_preinstalled_bindings = false

-- Omarchy defaults (shell autostart, bindings, envs, look and feel, input, window rules, theme).
require("default.hypr.omarchy")

-- Second half of the Ubuntu/GDM glue. It runs after the defaults because the
-- last hl.env wins and default/hypr/envs.lua writes OMARCHY_PATH and PATH with the
-- fallback when the variable is missing on the first parse (os.getenv never sees
-- an hl.env from the same parse). Mirrors env-bootstrap: Omarchy's bin first,
-- mise shims and ~/.local/bin last, no duplicates.
do
  hl.env("OMARCHY_PATH", omarchy_path)

  local home = os.getenv("HOME") or ""
  local bin_dir = omarchy_path .. "/bin"
  local seen = { [bin_dir] = true, ["/usr/share/omarchy/bin"] = true }
  local kept = { bin_dir }
  for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
    if not seen[entry] then
      seen[entry] = true
      table.insert(kept, entry)
    end
  end
  for _, dir in ipairs({ home .. "/.local/share/mise/shims", home .. "/.local/bin" }) do
    if not seen[dir] then
      seen[dir] = true
      table.insert(kept, dir)
    end
  end
  hl.env("PATH", table.concat(kept, ":"))
end

-- Personal overrides. Loaded after the defaults, so they win.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Dynamic toggle flags (omarchy-toggle-*).
require("default.hypr.toggles")

-- Any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
