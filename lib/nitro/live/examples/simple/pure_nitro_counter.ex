defmodule Nitro.Live.Examples.Simple.PureNitroCounter do
  @moduledoc """
  The exact same feature as `Nitro.Live.Examples.Simple.Counter` (an increment/
  decrement counter), built the classic nitro/Nitrogen way instead: no
  `Nitro.Live` runtime at all. No `Socket`, no `Runtime.mount/dispatch`, no
  scoped `push_patch/2`.

  State lives directly in the process dictionary via nitro's own
  `nitro:state/1,2` (literally `erlang:get/1` and `erlang:put/2` --
  `Nitro.Live.Runtime`'s own moduledoc credits this as its precedent).
  Every event rebuilds the whole subtree and sends it over the wire as a
  full `outerHTML` replace via `nitro:update/2` -- there is no
  component-level diffing below the Live layer, so a postback here can only
  ever say "here is the new HTML for this whole node", never "here is what
  changed inside it" (compare `Nitro.Live.Examples.Simple.PureLivePage`, which
  builds the identical UI and sends a scoped morphdom patch instead).

  This is also the shape `scripts/benchmark.exs`'s "pure nitro" side
  measures, made into a real, wire-postback-driven page module instead of a
  benchmark-only pure function.
  """

  import NITRO, only: [panel: 1, span: 1, button: 1]

  @id "pure-counter"

  def event(:init) do
    :nitro.state(:pure_nitro_counter_count, 0)
    render_and_push()
  end

  def event(:inc), do: bump(1)
  def event(:dec), do: bump(-1)

  defp bump(delta) do
    :nitro.state(:pure_nitro_counter_count, count() + delta)
    render_and_push()
  end

  defp count, do: :nitro.state(:pure_nitro_counter_count)

  defp render_and_push do
    :nitro.update(to_charlist(@id), render())
    []
  end

  def render do
    panel(
      id: to_charlist(@id),
      class: "counter",
      body: [
        span(body: ["Count: #{count()}"]),
        button(body: ["+"], postback: :inc, delegate: __MODULE__),
        button(body: ["-"], postback: :dec, delegate: __MODULE__)
      ]
    )
  end
end
