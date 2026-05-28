-- DP-1: ungerade Workspaces
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true,  persistent = true })
hl.workspace_rule({ workspace = "3", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "5", monitor = "DP-1", persistent = true })
hl.workspace_rule({ workspace = "7", monitor = "DP-1", persistent = false })
hl.workspace_rule({ workspace = "9", monitor = "DP-1", persistent = false })

-- DP-2: gerade Workspaces
hl.workspace_rule({ workspace = "2", monitor = "DP-2", default = true,  persistent = true })
hl.workspace_rule({ workspace = "4", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "6", monitor = "DP-2", persistent = true })
hl.workspace_rule({ workspace = "8", monitor = "DP-2", persistent = false })
hl.workspace_rule({ workspace = "10", monitor = "DP-2", persistent = false })

-- Workspace-Rule: keine Dekorationen, kein Gap
hl.workspace_rule({
    workspace   = "special:games",
    gaps_in     = 0,
    gaps_out    = 0,
    no_rounding = true,
    no_shadow = true,
    no_border = true,
    animation = "",
})
