defmodule Nitro.Live.Form do
  @moduledoc """
  Form support for Nitro.Live, built on nitro's own pre-existing
  `source`/`querySource`/Linked-args wiring -- fully implemented already
  (`action_event.erl`'s `data/2`, `priv/js/nitro.js`'s `querySource`,
  `nitro_n2o.erl`'s `render_ev/4` putting each collected value into the
  process dictionary before calling `Module:event/1`), just never exposed
  at the Nitro.Live layer until now.

  ## Submit-style: several fields, one postback

  Any postback-carrying element accepts a `source:` list of *other*
  elements' ids. Give a button one and, alongside the click, the real
  N2O flow reads each listed id's current DOM value (`querySource/1` --
  `.value` for text inputs, `.checked` for checkboxes/radios, a
  `{year,month,day}` tuple for date inputs) and puts it in the process
  dictionary *before* `handle_event/3` runs, keyed by that same id (as
  whatever Erlang type you passed as the source id -- a plain Elixir
  string source id comes back as a binary key). Read it with `value/1`/
  `values/1` inside `handle_event/3`:

      <input id="name"/>
      <input id="email"/>
      <button source={["name", "email"]} postback={live_event(@live_id, :save)} delegate={Nitro.Live.Dispatcher}>Save</button>

      def handle_event(:save, _params, socket) do
        %{"name" => name, "email" => email} = Form.values(["name", "email"])
        ...
      end

  ## Change-tracking: fire on every keystroke

  No nitro element lets you pick which DOM event triggers *its own*
  postback (every element hardcodes `click`), but every element record
  has a generic `actions:` field that gets `nitro:wire/1`'d automatically
  at render time regardless of element type
  (`wf_render_elements:render_element/1` checks it unconditionally,
  before dispatching to the element's own renderer) -- `live_change/4`
  just builds the `#event{}` value to put there, wired directly onto the
  field itself instead of a separate button:

      <input id="query" actions={Form.live_change("query", live_event(@live_id, {:search, :query}), Nitro.Live.Dispatcher)}/>

      def handle_event({:search, :query}, _params, socket) do
        Socket.assign(socket, :query, Form.value("query"))
      end

  `source` defaults to `[id]` (the field reports its own new value on
  every `input` event); pass `event: "change"` in `opts` to fire on blur
  instead of every keystroke, or `source: [...]` to also collect other
  fields' values alongside this one.
  """

  require NITRO

  @doc """
  Reads one field's value collected via `source:`/`live_change/4` for the
  postback currently being handled -- only meaningful inside
  `handle_event/3` (or something it calls), the same connection process
  N2O just wrote it into. `id` must be the exact value (and Erlang type)
  used as the source id.
  """
  def value(id), do: Process.get(id)

  @doc "Reads several fields at once -- see `value/1`."
  def values(ids), do: Map.new(ids, &{&1, Process.get(&1)})

  @doc """
  Builds an `#event{}` value for a field's own `actions:` attribute,
  wiring that field's own DOM event (`input` by default) directly to
  `postback` -- see this module's moduledoc for why a separate mechanism
  from a button's `postback:` is needed at all.
  """
  def live_change(id, postback, delegate, opts \\ []) do
    NITRO.event(
      type: Keyword.get(opts, :event, "input"),
      target: id,
      postback: postback,
      delegate: delegate,
      source: Keyword.get(opts, :source, [id])
    )
  end
end
