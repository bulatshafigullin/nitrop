{:ok, _} = Nitro.Live.Examples.Simple.Server.start(8080)
IO.puts("listening on http://localhost:8080")
Process.sleep(:infinity)
