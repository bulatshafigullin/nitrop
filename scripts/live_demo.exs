alias Nitro.Live.{Runtime, Examples.Simple.Counter}

html = fn tree -> tree |> :wf_render.render() |> IO.iodata_to_binary() end

IO.puts("== mount + initial render ==")
Runtime.mount(Counter, "counter1")
initial = Runtime.render_root("counter1")
IO.puts(html.(initial))

IO.puts("\n== dispatch :inc directly (module call, in-process) ==")
{:changed, tree1} = Runtime.dispatch("counter1", :inc, %{})
IO.puts(html.(tree1))

IO.puts("\n== dispatch :inc again ==")
{:changed, tree2} = Runtime.dispatch("counter1", :inc, %{})
IO.puts(html.(tree2))

IO.puts("\n== dispatch :noop (assigns unchanged -> no re-render) ==")
result = Runtime.dispatch("counter1", :noop, %{})
IO.inspect(result, label: "result")

IO.puts("\n== same event, but round-tripped through nitro's real postback wire format ==")
postback = Nitro.Live.live_event("counter1", :dec)
pickled = :nitro.pickle(postback)
IO.puts("pickled (base64, what actually goes to/from the browser): #{pickled}")
depickled = :nitro.depickle(pickled)

IO.puts("\n== Dispatcher.event/1 on that depickled postback -- dispatches AND pushes the patch, exactly what a real click does ==")
:nitro.actions([])
Nitro.Live.Dispatcher.event(depickled)

patch_js =
  :nitro.actions()
  |> Enum.map(fn {:wire, :action, _, _, :action_wire, payload, _} -> payload end)
  |> Enum.find(&(is_list(&1) and List.starts_with?(&1, ~c"NitroLive")))

IO.puts(patch_js)
IO.puts("(load priv/static/nitro-live.js as a <script type=\"module\"> and eval this to apply it -- see test/js for the browser-side proof it patches in place)")
