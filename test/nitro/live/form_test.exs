defmodule Nitro.Live.FormTest do
  @moduledoc """
  Nitro.Live.Form sits on top of nitro's real `source`/`querySource`
  wiring: in production, `nitro_n2o.erl`'s `render_ev/4` reads each
  collected value out of the postback's Linked args and
  `erlang:put/2`s it into the process dictionary *before*
  `Module:event/1` (and so `handle_event/3`) ever runs -- see
  `Nitro.Live.Form`'s moduledoc. `Runtime.dispatch/3` is called directly
  in this test suite (same as everywhere else in this repo), which
  bypasses that N2O layer entirely, so tests that exercise
  `Form.value/1`/`values/1` simulate it explicitly with `Process.put/2`,
  matching exactly what `render_ev/4` would have already done by the time
  a real click reaches `handle_event/3`. The wire-JS tests below prove
  separately, at the protocol level, that a real click *would* produce
  those exact puts.
  """
  use ExUnit.Case, async: true

  alias Nitro.Live.{Runtime, Form}
  alias Nitro.Live.Examples.Simple.ContactForm

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  defp html(tree), do: tree |> :wf_render.render() |> IO.iodata_to_binary()

  setup do
    require N2O
    Process.put(:context, N2O.cx())
    :nitro.actions([])
    :ok
  end

  defp wire_js do
    actions = :nitro.actions()
    :nitro.actions([])
    first = :nitro.render(actions)
    second = :nitro.render(:nitro.actions())
    :nitro.actions([])
    IO.iodata_to_binary([first, second])
  end

  describe "Form.value/1 and values/1" do
    test "read whatever is in the process dictionary under that id" do
      Process.put("name", "Alice")
      assert Form.value("name") == "Alice"
      assert Form.value("missing") == nil
    end

    test "values/1 reads several at once" do
      Process.put("name", "Alice")
      Process.put("email", "alice@example.com")
      assert Form.values(["name", "email"]) == %{"name" => "Alice", "email" => "alice@example.com"}
    end
  end

  describe "wire protocol -- proving a real click/keystroke WOULD populate those values" do
    test "a button's source: list produces one querySource(...) call per field, keyed by that field's id" do
      require NITRO

      tree =
        NITRO.panel(
          body: [
            NITRO.input(id: "name"),
            NITRO.button(source: ["name", "email"], postback: :save, delegate: __MODULE__)
          ]
        )

      html(tree)
      js = wire_js()
      assert js =~ "tuple(bin('name'),querySource('name'))"
      assert js =~ "tuple(bin('email'),querySource('email'))"
      assert js =~ "addEventListener('click'"
    end

    test "Form.live_change/4 wires the field's OWN input event, not a click on some other element" do
      require NITRO
      tree = NITRO.input(id: "query", actions: Form.live_change("query", {:search}, __MODULE__))

      html(tree)
      js = wire_js()
      assert js =~ "qi('query')"
      assert js =~ "addEventListener('input'"
      assert js =~ "tuple(bin('query'),querySource('query'))"
    end

    test "live_change/4 accepts a different event type and an explicit source list" do
      require NITRO
      tree = NITRO.input(id: "amount", actions: Form.live_change("amount", {:recalc}, __MODULE__, event: "change", source: ["amount", "currency"]))

      html(tree)
      js = wire_js()
      assert js =~ "addEventListener('change'"
      assert js =~ "tuple(bin('amount'),querySource('amount'))"
      assert js =~ "tuple(bin('currency'),querySource('currency'))"
    end
  end

  describe "ContactForm (Nitro.Live)" do
    test "mounts with no saved contact and the full name list" do
      id = uid("contact-form")
      Runtime.mount(ContactForm, id)
      out = html(Runtime.render_root(id))
      assert out =~ "10 name(s)"
      refute out =~ "class=\"saved\""
    end

    test ":save reads both fields via Form.values/1, simulating what render_ev/4 would have put there" do
      id = uid("contact-form")
      Runtime.mount(ContactForm, id)

      Process.put("cf-name", "Alice")
      Process.put("cf-email", "alice@example.com")
      assert {:changed, tree} = Runtime.dispatch(id, :save, %{})
      assert html(tree) =~ "Saved: Alice &lt;alice@example.com&gt;"
    end

    test ":filter narrows the results and remembers the current filter text" do
      id = uid("contact-form")
      Runtime.mount(ContactForm, id)

      Process.put("cf-filter", "al")
      assert {:changed, tree} = Runtime.dispatch(id, :filter, %{})
      out = html(tree)
      assert out =~ "1 name(s)"
      assert out =~ "Alice"
      refute out =~ "Bob"
    end

    test "an empty filter after a narrower one restores the full list" do
      id = uid("contact-form")
      Runtime.mount(ContactForm, id)

      Process.put("cf-filter", "al")
      Runtime.dispatch(id, :filter, %{})

      Process.put("cf-filter", "")
      assert {:changed, tree} = Runtime.dispatch(id, :filter, %{})
      assert html(tree) =~ "10 name(s)"
    end
  end
end
