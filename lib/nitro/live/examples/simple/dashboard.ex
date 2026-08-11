defmodule Nitro.Live.Examples.Simple.Dashboard do
  @moduledoc """
  Root live view embedding two independent `Toggle` components, to prove
  nested-component support: bumping the parent's own counter re-renders the
  whole dashboard subtree (via `Runtime.component/3` re-embedding both
  toggles inline) without resetting either toggle's on/off state, and
  flipping a toggle patches *only* that toggle's own id/subtree.

  Also renders a plain `#textbox{}` whose `value` attribute changes every
  render (`"server-note-\#{renders}"`) -- this is `nitro-live.js`'s focus
  preservation test, for real, in the actual DOM: click "re-render parent"
  while the field is focused and holds unsaved typing, and the server's
  ever-changing value must NOT clobber it (see TODO.md).

  And embeds `Nitro.Live.Examples.Simple.HeexCounter`, a component authored with
  `~H` instead of hand-written `NITRO.panel(...)` calls, proving the two
  authoring styles interoperate for real -- same postback wiring, same
  scoped `push_patch/2`, in the same running server/browser as everything
  else on this page.
  """

  use Nitro.Live
  import NITRO, only: [panel: 1, span: 1, button: 1, textbox: 1]
  alias Nitro.Live.{Runtime, Socket}

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, :renders, 1)

  @impl true
  def render(assigns) do
    panel(
      class: "dashboard",
      body: [
        span(id: "renders", body: ["Parent rendered #{assigns.renders} time(s)"]),
        button(
          body: ["re-render parent"],
          postback: Nitro.Live.live_event(assigns.live_id, :bump),
          delegate: Nitro.Live.Dispatcher
        ),
        Runtime.component(Nitro.Live.Examples.Simple.Toggle, "toggle-a", %{on: false}),
        Runtime.component(Nitro.Live.Examples.Simple.Toggle, "toggle-b", %{on: true}),
        Runtime.component(Nitro.Live.Examples.Simple.HeexCounter, "heex-counter", %{}),
        textbox(
          id: "note-input",
          # #textbox.disabled defaults to `undefined`, not `[]` -- and
          # element_textbox.erl's disabled-check only treats a literal `[]`
          # as "not disabled", so every textbox renders disabled unless this
          # is passed explicitly. A real nitro quirk, not ours to fix here.
          disabled: [],
          placeholder: "type here, then click re-render parent",
          value: "server-note-#{assigns.renders}"
        )
      ]
    )
  end

  @impl true
  def handle_event(:bump, _params, socket), do: Socket.assign(socket, :renders, socket.assigns.renders + 1)
end
