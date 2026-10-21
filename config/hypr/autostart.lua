-- Extra processes at startup. The shell, udiskie, import-environment and so on
-- are already launched by $OMARCHY_PATH/default/hypr/autostart.lua.
-- OMARCHY_PATH and PATH for the direct GDM session are handled at the top of hyprland.lua.

-- Ubuntu/GDM: in the packaged `Hyprland` entry (the fallback, no uwsm)
-- graphical-session.target never activates (RefuseManualStart), so Omarchy's
-- user units (WantedBy=graphical-session.target) do not start on their own;
-- start them by hand after the import-environment done by Omarchy's autostart.
-- In the uwsm session (the autologin target) the target pulls them in and this
-- start is redundant and harmless.
o.exec_on_start(
  "sleep 3 && systemctl --user start bt-agent.service omarchy-sleep-lock.service omarchy-crash-watch.service"
    .. " omarchy-recover-internal-monitor.service omarchy-tailscale-receive.service omarchy-migrate-notify.service"
    .. " voxtype.service"
)

-- o.launch_on_start("my-service")
