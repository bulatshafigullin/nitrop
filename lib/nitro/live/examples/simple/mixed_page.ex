defmodule Nitro.Live.Examples.Simple.MixedPage do
  @moduledoc """
  Progressive-adoption example: a page authored the classic nitro way (own
  `event/1`, own `nitro:state/1,2`, a full `nitro:update/2` replace for its
  own content -- same style as `Nitro.Live.Examples.Simple.PureNitroCounter`) that
  drops a single `Nitro.Live` component in as an island.

  `Runtime.component/3`'s scoped `push_patch/2` only ever touches that
  island's own subtree -- clicking the embedded `Toggle` never re-renders or
  resends the classic content around it, and clicking the classic `+`/`-`
  buttons rewrites this page's own root (island included, but the island is
  just re-rendered from its own already-current state, not reset) without
  going anywhere near `Nitro.Live.Dispatcher`. Proves the two authoring
  styles can share one page/process without either one needing to know
  about the other beyond this page module wiring both.

  One real gap worth knowing before adopting this pattern: `Runtime.component/3`
  calls here happen *outside* any `Nitro.Live.Runtime.render_scoped/1` (this
  page itself is never a Live module), so the usual per-render child
  garbage-collection (`Runtime.gc_stale_children/2`, see
  `Nitro.Live.Runtime`'s moduledoc) never runs for it -- if a future version
  of this page ever stopped embedding the island, its socket would leak for
  the life of the connection instead of being torn down automatically the
  way a Live-authored parent's own children are. `Runtime.unmount/1` exists
  for exactly this but is private; embedding a Live component in a
  non-Live page is fine for an island that's always present (as here), less
  so for one that's meant to come and go.
  """

  import NITRO, only: [panel: 1, span: 1, button: 1]
  alias Nitro.Live.{Runtime, Dispatcher, Examples.Simple.Toggle}

  @id "mixed-root"
  @live_child_id "mixed-toggle"

  def event(:init) do
    Runtime.mount(Toggle, @live_child_id, %{on: false})
    :nitro.state(:mixed_page_count, 0)
    render_and_push()
  end

  def event(:inc), do: bump(1)
  def event(:dec), do: bump(-1)
  def event({:live_event, _id, _name, _params} = postback), do: Dispatcher.event(postback)

  defp bump(delta) do
    :nitro.state(:mixed_page_count, count() + delta)
    render_and_push()
  end

  defp count, do: :nitro.state(:mixed_page_count)

  defp render_and_push do
    :nitro.update(to_charlist(@id), render())
    []
  end

  def render do
    panel(
      id: to_charlist(@id),
      class: "mixed",
      body: [
        span(body: "Plain nitro count: #{count()}"),
        button(body: "+", postback: :inc, delegate: __MODULE__),
        button(body: "-", postback: :dec, delegate: __MODULE__),
        Runtime.component(Toggle, @live_child_id, %{})
      ]
    )
  end
end
