# Same as run_server.exs, but with Nitro.Live.Reload watching lib/ --
# edit and save any .ex file while this is running and every connected
# browser tab reloads on its own, no manual refresh, no server restart.
# Requires MIX_ENV=dev (fs is an only: :dev dependency): MIX_ENV=dev mix
# run scripts/run_server_dev.exs

{:ok, _} = Nitro.Live.Reload.start("lib")
{:ok, _} = Nitro.Live.Examples.Simple.Server.start(8080)
IO.puts("listening on http://localhost:8080 (auto-reload on lib/ changes)")
Process.sleep(:infinity)
