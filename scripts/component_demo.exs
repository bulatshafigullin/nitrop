alias Nitro.Live.{Runtime, Examples.Simple.Dashboard}

html = fn tree -> tree |> :wf_render.render() |> IO.iodata_to_binary() end

IO.puts("== mount dashboard (mounts toggle-a=off, toggle-b=on inline) ==")
Runtime.mount(Dashboard, "dashboard")
IO.puts(html.(Runtime.render_root("dashboard")))

IO.puts("\n== flip toggle-a directly ==")
{:changed, toggle_tree} = Runtime.dispatch("toggle-a", :flip, %{})
IO.puts("patch target/subtree (only toggle-a, not the whole dashboard):")
IO.puts(html.(toggle_tree))

IO.puts("\n== bump the parent (re-render dashboard) -- toggle-a must still read ON, toggle-b still ON ==")
{:changed, dashboard_tree} = Runtime.dispatch("dashboard", :bump, %{})
IO.puts(html.(dashboard_tree))

IO.puts("\n== flip toggle-b, then bump parent again -- both toggles' state must survive ==")
Runtime.dispatch("toggle-b", :flip, %{})
{:changed, dashboard_tree2} = Runtime.dispatch("dashboard", :bump, %{})
IO.puts(html.(dashboard_tree2))
