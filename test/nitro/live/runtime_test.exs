defmodule Nitro.Live.RuntimeTest do
  use ExUnit.Case, async: true

  alias Nitro.Live.{Runtime, Dispatcher}
  alias Nitro.Live.Fixtures.{Counter, Crasher, Toggle, ToggleWithUpdate, Parent}

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  defp html(tree), do: tree |> :wf_render.render() |> IO.iodata_to_binary()

  describe "mount/2,3 + render_root/1" do
    test "mounts, runs mount/2, and renders the wrapped tree" do
      id = uid("counter")
      Runtime.mount(Counter, id, %{count: 5})
      assert html(Runtime.render_root(id)) == "<div id=\"#{id}\"><span>count=5</span></div>"
    end

    test "render_root/1 raises for an id that was never mounted" do
      assert_raise RuntimeError, ~r/no socket mounted/, fn ->
        Runtime.render_root(uid("never-mounted"))
      end
    end
  end

  describe "dispatch/3" do
    test "returns {:changed, tree} and re-renders when assigns change" do
      id = uid("counter")
      Runtime.mount(Counter, id)
      assert {:changed, tree} = Runtime.dispatch(id, :inc, %{})
      assert html(tree) == "<div id=\"#{id}\"><span>count=1</span></div>"
    end

    test "returns :unchanged and does not re-render when assigns don't change" do
      id = uid("counter")
      Runtime.mount(Counter, id)
      assert Runtime.dispatch(id, :noop, %{}) == :unchanged
    end

    test "state accumulates across multiple dispatches" do
      id = uid("counter")
      Runtime.mount(Counter, id)
      Runtime.dispatch(id, :inc, %{})
      {:changed, tree} = Runtime.dispatch(id, :inc, %{})
      assert html(tree) == "<div id=\"#{id}\"><span>count=2</span></div>"
    end

    test "a crash in handle_event is caught, logged, and leaves the socket untouched" do
      id = uid("crasher")
      Runtime.mount(Crasher, id)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Runtime.dispatch(id, :boom, %{}) == :unchanged
        end)

      assert log =~ "handle_event/render crashed"
      assert log =~ inspect(id)
      assert log =~ "simulated crash"

      # socket is exactly as it was before the crash
      assert html(Runtime.render_root(id)) == "<div id=\"#{id}\"><span>count=0</span></div>"
    end

    test "the connection is still usable after a crash" do
      id = uid("crasher")
      Runtime.mount(Crasher, id)
      ExUnit.CaptureLog.capture_log(fn -> Runtime.dispatch(id, :boom, %{}) end)
      assert {:changed, tree} = Runtime.dispatch(id, :inc, %{})
      assert html(tree) == "<div id=\"#{id}\"><span>count=1</span></div>"
    end

    test "dispatching to an unmounted id raises rather than silently no-op-ing" do
      assert_raise RuntimeError, ~r/no socket mounted/, fn ->
        Runtime.dispatch(uid("ghost"), :inc, %{})
      end
    end
  end

  describe "component/3" do
    test "mounts a child once and reuses its state on later calls, ignoring new params by default" do
      child = uid("child")

      tree1 = Runtime.component(Toggle, child, %{on: false})
      assert html(tree1) == "<div id=\"#{child}\"><button type=\"button\">off</button></div>"

      Runtime.dispatch(child, :flip, %{})
      # re-embedding with different params (on: false) must NOT reset the flipped state
      tree2 = Runtime.component(Toggle, child, %{on: false})
      assert html(tree2) == "<div id=\"#{child}\"><button type=\"button\">on</button></div>"
    end

    test "update/2 lets a parent push new params into an already-mounted component" do
      id = uid("labelled")
      Runtime.component(ToggleWithUpdate, id, %{label: "first"})
      assert html(Runtime.component(ToggleWithUpdate, id, %{label: "second"})) =~ "second"
    end

    test "without update/2, later params are ignored (Phoenix's LiveComponent default)" do
      id = uid("toggle")
      Runtime.component(Toggle, id, %{on: false})
      Runtime.dispatch(id, :flip, %{})
      assert html(Runtime.component(Toggle, id, %{on: false})) =~ ">on<"
    end

    test "a component's own dispatch patches only its own subtree" do
      id = uid("toggle")
      Runtime.component(Toggle, id, %{on: false})
      assert {:changed, tree} = Runtime.dispatch(id, :flip, %{})
      assert html(tree) == "<div id=\"#{id}\"><button type=\"button\">on</button></div>"
    end
  end

  describe "component garbage collection" do
    test "a child no longer embedded by its parent's render is unmounted" do
      parent_id = uid("parent")
      Runtime.mount(Parent, parent_id)
      child_id = parent_id <> "-child"

      Runtime.render_root(parent_id)
      Runtime.dispatch(child_id, :flip, %{})
      assert html(Runtime.render_root(parent_id)) =~ ">on<"

      {:changed, hidden_tree} = Runtime.dispatch(parent_id, :hide_child, %{})
      assert html(hidden_tree) == "<div id=\"#{parent_id}\"><div></div></div>"

      assert_raise RuntimeError, ~r/no socket mounted/, fn ->
        Runtime.dispatch(child_id, :flip, %{})
      end
    end

    test "re-showing a hidden child mounts it fresh (its old state was really torn down)" do
      parent_id = uid("parent")
      Runtime.mount(Parent, parent_id)
      child_id = parent_id <> "-child"

      Runtime.render_root(parent_id)
      Runtime.dispatch(child_id, :flip, %{})
      Runtime.dispatch(parent_id, :hide_child, %{})
      {:changed, shown_tree} = Runtime.dispatch(parent_id, :show_child, %{})

      assert html(shown_tree) =~ ">off<"
    end
  end

  describe "push_patch/2" do
    test "wires a NitroLive.patch(...) call with patch-then-bindings ordering" do
      id = uid("counter")
      Runtime.mount(Counter, id)
      tree = Runtime.render_root(id)

      :nitro.actions([])
      Runtime.push_patch(id, tree)
      actions = :nitro.actions()

      assert [{:wire, :action, _, _, :action_wire, patch_js, _} | _rest] = actions
      assert is_list(patch_js)
      assert List.starts_with?(patch_js, ~c"NitroLive.patch(")
      assert List.to_string(patch_js) =~ ~s(NitroLive.patch("#{id}",)
    end
  end

  describe "reconnect persistence" do
    test "state survives a mount in a completely different process given the same session id" do
      session_id = uid("session")
      live_id = uid("persisted")

      task1 =
        Task.async(fn ->
          Runtime.mount(Toggle, live_id, %{on: false}, session_id)
          Runtime.dispatch(live_id, :flip, %{})
          :ok
        end)

      Task.await(task1)

      task2 =
        Task.async(fn ->
          socket = Runtime.mount(Toggle, live_id, %{on: false}, session_id)
          socket.assigns.on
        end)

      assert Task.await(task2) == true
    end

    test "without a session id, state does NOT survive a process boundary" do
      live_id = uid("not-persisted")

      task1 =
        Task.async(fn ->
          Runtime.mount(Toggle, live_id, %{on: false})
          Runtime.dispatch(live_id, :flip, %{})
          :ok
        end)

      Task.await(task1)

      task2 =
        Task.async(fn ->
          socket = Runtime.mount(Toggle, live_id, %{on: false})
          socket.assigns.on
        end)

      assert Task.await(task2) == false
    end
  end

  describe "Dispatcher.event/1" do
    test "{:live_event, id, name, params} dispatches and pushes a patch when state changed" do
      id = uid("counter")
      Runtime.mount(Counter, id)

      :nitro.actions([])
      assert Dispatcher.event({:live_event, id, :inc, %{}}) == []

      actions = :nitro.actions()
      assert [{:wire, :action, _, _, :action_wire, patch_js, _}] = actions
      assert List.to_string(patch_js) =~ "count=1"
    end

    test "no patch is wired when the event doesn't change state" do
      id = uid("counter")
      Runtime.mount(Counter, id)

      :nitro.actions([])
      Dispatcher.event({:live_event, id, :noop, %{}})
      assert :nitro.actions() == []
    end

    test "unrecognized postbacks are ignored, not crashed on" do
      assert Dispatcher.event(:something_else) == []
      assert Dispatcher.event({:direct, "whatever"}) == []
    end
  end
end
