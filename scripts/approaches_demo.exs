# Three ways to build the same interactive counter/toggle UI, side by side:
#   1. pure nitro       -- Nitro.Live.Examples.Simple.PureNitroCounter
#   2. pure Nitro.Live   -- Nitro.Live.Examples.Simple.PureLivePage (wraps Counter)
#   3. mixed             -- Nitro.Live.Examples.Simple.MixedPage (classic root + a Live island)
# Run: mix run scripts/approaches_demo.exs

alias Nitro.Live.Examples.Simple.{PureNitroCounter, PureLivePage, MixedPage}

# nitro:update/2 (the plain-nitro path) eagerly renders queued button-click
# bindings, which needs a #cx{} in get(context) -- in a real server this is
# already set by nitro_n2o.erl before any event/1 call; here we're not
# behind a real connection, so seed a default one ourselves.
require N2O
Process.put(:context, N2O.cx())

# Mirrors nitro_n2o.erl's render_actions/1 -- the real server's final pass
# over one event's whole accumulated action queue, turning every wired
# action (outerHTML replaces, scoped patches, raw #event{} click bindings
# that push_patch/2 defers instead of rendering eagerly) into the JS text
# actually sent over the wire. Double-render because rendering can itself
# queue more actions (nitro_n2o.erl's own comment: "actions could generate
# actions").
wire_js = fn ->
  actions = :nitro.actions()
  :nitro.actions([])
  first = :nitro.render(actions)
  second = :nitro.render(:nitro.actions())
  :nitro.actions([])
  IO.iodata_to_binary([first, second])
end

pickled = fn id, event -> Nitro.Live.live_event(id, event) |> :nitro.pickle() |> :nitro.depickle() end

IO.puts("== 1. pure nitro (PureNitroCounter) ==")
IO.puts("-- event(:init): builds + sends the whole node as one outerHTML replace --")
:nitro.actions([])
PureNitroCounter.event(:init)
IO.puts(wire_js.())

IO.puts("\n-- event(:inc) x2: EVERY click resends the whole node again, same as :init --")
:nitro.actions([])
PureNitroCounter.event(:inc)
PureNitroCounter.event(:inc)
IO.puts(wire_js.())

IO.puts("\n\n== 2. pure Nitro.Live (PureLivePage wrapping Counter) ==")
IO.puts("-- event(:init): mount + scoped push_patch (NitroLive.patch, not outerHTML=) --")
:nitro.actions([])
PureLivePage.event(:init)
IO.puts(wire_js.())

IO.puts("\n-- postback :inc, round-tripped through the real pickle/depickle wire format --")
:nitro.actions([])
PureLivePage.event(pickled.("pure-live-counter", :inc))
IO.puts(wire_js.())

IO.puts(
  "\n-- postback :noop (Counter.handle_event(:noop, ...) leaves assigns untouched) -- " <>
    ":unchanged, NOTHING is sent, not even a same-value rewrite: --"
)

:nitro.actions([])
PureLivePage.event(pickled.("pure-live-counter", :noop))
IO.puts(inspect(:nitro.actions()))

IO.puts("\n\n== 3. mixed page (MixedPage): classic root + one Live-authored Toggle island ==")
IO.puts("-- event(:init) --")
:nitro.actions([])
MixedPage.event(:init)
IO.puts(wire_js.())

IO.puts("\n-- classic postback :inc -- rewrites the WHOLE mixed-root outerHTML (island re-rendered inline, state untouched) --")
:nitro.actions([])
MixedPage.event(:inc)
IO.puts(wire_js.())

IO.puts("\n-- Live postback on the embedded Toggle -- patches ONLY the island's own subtree, never mixed-root --")
:nitro.actions([])
MixedPage.event(pickled.("mixed-toggle", :flip))
IO.puts(wire_js.())

IO.puts(
  "\n-- classic postback :dec again -- island keeps its flipped state (it's not rebuilt from " <>
    "scratch, Runtime.component/3 just re-renders the same live socket) --"
)

:nitro.actions([])
MixedPage.event(:dec)
IO.puts(wire_js.())
