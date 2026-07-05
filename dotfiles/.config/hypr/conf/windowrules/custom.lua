local function games_window_rule(match)
hl.window_rule({
    match       = match,
    workspace   = "special:games",
    monitor     = "DP-2",
    content     = "game",
    fullscreen  = true,
    immediate   = true,
    no_blur     = true,
    no_anim     = true,
    no_shadow   = true,
    opaque      = true,
    border_size = 0,
    rounding    = 0,
})
end

games_window_rule({ class = "gamescope" })
games_window_rule({ class = "steam_app_.*" })
