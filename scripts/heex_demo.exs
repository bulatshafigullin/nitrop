alias Nitro.Live.{Runtime, Examples.Simple.HeexCounter}

html = fn tree -> tree |> :wf_render.render() |> IO.iodata_to_binary() end

IO.puts("== mount + initial render (authored with ~H) ==")
Runtime.mount(HeexCounter, "heex-counter1")
IO.puts(html.(Runtime.render_root("heex-counter1")))

IO.puts("\n== dispatch :inc ==")
{:changed, tree1} = Runtime.dispatch("heex-counter1", :inc, %{})
IO.puts(html.(tree1))

IO.puts("\n== dispatch :dec ==")
{:changed, tree2} = Runtime.dispatch("heex-counter1", :dec, %{})
IO.puts(html.(tree2))
