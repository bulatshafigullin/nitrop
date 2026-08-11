defmodule Nitro.Live.ExamplesTest do
  @moduledoc """
  Covers the three "same counter/toggle feature, three ways" example page
  modules: PureNitroCounter (no Nitro.Live at all), PureLivePage (all
  Nitro.Live), MixedPage (a classic nitro page hosting one Live island).
  Each test seeds a #cx{} into `context` because `nitro:update/2` renders
  button click bindings eagerly (unlike push_patch/2, which defers that to
  the real server's own final action-render pass) -- see
  `scripts/approaches_demo.exs` for the same requirement, explained there.
  """
  use ExUnit.Case, async: true

  alias Nitro.Live.Examples.Simple.{PureNitroCounter, PureLivePage, MixedPage}

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

  defp pickled(id, event), do: Nitro.Live.live_event(id, event) |> :nitro.pickle() |> :nitro.depickle()

  describe "PureNitroCounter (pure nitro, no Nitro.Live)" do
    test "event(:init) renders count 0 as a full outerHTML replace" do
      PureNitroCounter.event(:init)
      js = wire_js()
      assert js =~ "qi('pure-counter')"
      assert js =~ "outerHTML"
      assert js =~ "Count: 0"
    end

    test "every postback resends the whole node -- no scoping below the raw record layer" do
      PureNitroCounter.event(:init)
      :nitro.actions([])
      PureNitroCounter.event(:inc)
      js = wire_js()
      assert js =~ "qi('pure-counter')"
      assert js =~ "Count: 1"

      :nitro.actions([])
      PureNitroCounter.event(:dec)
      assert wire_js() =~ "Count: 0"
    end
  end

  describe "PureLivePage (pure Nitro.Live)" do
    test "event(:init) mounts Counter and sends a scoped NitroLive.patch" do
      PureLivePage.event(:init)
      js = wire_js()
      assert js =~ "NitroLive.patch(\"pure-live-counter\","
      assert js =~ "Count: 0"
      refute js =~ "outerHTML"
    end

    test "a real pickled postback increments and patches only the counter subtree" do
      PureLivePage.event(:init)
      :nitro.actions([])
      PureLivePage.event(pickled("pure-live-counter", :inc))
      assert wire_js() =~ "Count: 1"
    end

    test "an event that leaves assigns unchanged sends nothing at all" do
      PureLivePage.event(:init)
      :nitro.actions([])
      PureLivePage.event(pickled("pure-live-counter", :noop))
      assert :nitro.actions() == []
    end
  end

  describe "MixedPage (classic nitro root + one Nitro.Live island)" do
    test "event(:init) renders the classic root and the embedded Toggle inline" do
      MixedPage.event(:init)
      js = wire_js()
      assert js =~ "qi('mixed-root')"
      assert js =~ "Plain nitro count: 0"
      assert js =~ "id=\"mixed-toggle\""
      assert js =~ "OFF"
    end

    test "a classic postback replaces the whole root, island included, without resetting island state" do
      MixedPage.event(:init)
      :nitro.actions([])
      MixedPage.event(pickled("mixed-toggle", :flip))
      :nitro.actions([])
      MixedPage.event(:inc)
      js = wire_js()
      assert js =~ "qi('mixed-root')"
      assert js =~ "Plain nitro count: 1"
      # island's flipped state survived being swept up in the classic full-page replace
      assert js =~ "ON"
      refute js =~ "OFF"
    end

    test "a Live postback on the embedded island patches only that island's own subtree" do
      MixedPage.event(:init)
      :nitro.actions([])
      MixedPage.event(pickled("mixed-toggle", :flip))
      js = wire_js()
      assert js =~ "NitroLive.patch(\"mixed-toggle\","
      refute js =~ "mixed-root"
      assert js =~ "ON"
    end
  end
end
