{:ok, _} = Nitro.Live.Examples.RimShop.Server.start(8081)
IO.puts("listening on http://localhost:8081")
Process.sleep(:infinity)
