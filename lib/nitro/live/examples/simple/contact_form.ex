defmodule Nitro.Live.Examples.Simple.ContactForm do
  @moduledoc """
  Demonstrates both of `Nitro.Live.Form`'s capabilities on one page:

  1. Submit-style, several fields collected at once -- "Save" reads both
     the name and email fields' current DOM values (via `source:` on the
     button) in a single click/postback. Neither field needs its own
     postback or any server round trip while typing.
  2. Change-tracking, one field -- the filter input fires a postback on
     every keystroke (`Form.live_change/4`) and the name list re-renders
     filtered live, no submit button involved.

  See `Nitro.Live.Form`'s moduledoc for how both are really nitro's own
  pre-existing `source`/`querySource`/`actions:` wiring, not a new
  protocol mechanism.
  """

  use Nitro.Live
  alias Nitro.Live.{Socket, Form, Dispatcher}

  @names ~w(Alice Bob Charlie Dana Erin Frank Grace Heidi Ivan Judy)

  @impl true
  def mount(_params, socket), do: Socket.assign(socket, %{saved: nil, filter: "", results: @names})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contact-form">
      <section class="submit-form">
        <h3>Save a contact</h3>
        <label>Name <input id="cf-name" placeholder="name"/></label>
        <label>Email <input id="cf-email" placeholder="email"/></label>
        <button source={["cf-name", "cf-email"]} postback={live_event(@live_id, :save)} delegate={Dispatcher}>Save</button>
        <p :if={@saved} class="saved">Saved: {@saved}</p>
      </section>

      <section class="live-filter">
        <h3>Filter as you type</h3>
        <input
          id="cf-filter"
          placeholder="filter names..."
          actions={Form.live_change("cf-filter", live_event(@live_id, :filter), Dispatcher)}
        />
        <p class="count">{length(@results)} name(s)</p>
        <ul>
          <li :for={name <- @results}>{name}</li>
        </ul>
      </section>
    </div>
    """
  end

  @impl true
  def handle_event(:save, _params, socket) do
    %{"cf-name" => name, "cf-email" => email} = Form.values(["cf-name", "cf-email"])
    Socket.assign(socket, :saved, "#{name} <#{email}>")
  end

  def handle_event(:filter, _params, socket) do
    filter = Form.value("cf-filter") || ""
    matches = Enum.filter(@names, &String.contains?(String.downcase(&1), String.downcase(filter)))
    socket |> Socket.assign(:filter, filter) |> Socket.assign(:results, matches)
  end
end
