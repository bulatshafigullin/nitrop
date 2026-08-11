defmodule Nitro.Live.HTMLTest do
  use ExUnit.Case, async: true

  alias Nitro.Live.Runtime
  alias Nitro.Live.Fixtures.{HeexCounter, HeexToggle, HeexKitchenSink}

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
  defp html(tree), do: tree |> :wf_render.render() |> IO.iodata_to_binary()

  describe "~H produces the same nitro record tree hand-written NITRO calls would" do
    test "renders, and text interpolation reflects assigns" do
      id = uid("heex-counter")
      Runtime.mount(HeexCounter, id)
      assert html(Runtime.render_root(id)) == "<div id=\"#{id}\"><span>count=0</span></div>"
    end

    test "state updates and re-renders through the normal dispatch/push_patch path" do
      id = uid("heex-counter")
      Runtime.mount(HeexCounter, id)
      assert {:changed, tree} = Runtime.dispatch(id, :inc, %{})
      assert html(tree) == "<div id=\"#{id}\"><span>count=1</span></div>"
    end

    test "postback + delegate attribute expressions wire a real click binding" do
      id = uid("heex-toggle")
      tree = Runtime.component(HeexToggle, id, %{on: false})
      out = html(tree)
      assert out =~ "<div id=\"#{id}\">"
      # postback set -> element_button.erl gives the button its own auto id
      assert out =~ ~r{<button id="auto-\d+" type="button">off</button>}

      :nitro.actions([])
      Runtime.push_patch(id, tree)
      actions = :nitro.actions()
      assert [{:wire, :action, _, _, :action_wire, wire_js, _} | _] = actions
      assert is_list(wire_js)

      Runtime.dispatch(id, :flip, %{})
      assert html(Runtime.component(HeexToggle, id, %{on: false})) =~ ">on</button>"
    end
  end

  describe "directives" do
    test ":if renders the true branch and omits the false one" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      out = html(Runtime.render_root(id))
      assert out =~ "<p>shown</p>"
      refute out =~ "<p>hidden</p>"
    end

    test ":if flips correctly across a dispatch" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      {:changed, tree} = Runtime.dispatch(id, :toggle, %{})
      out = html(tree)
      assert out =~ "<p>hidden</p>"
      refute out =~ "<p>shown</p>"
    end

    test ":for renders one node per item, in order" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      out = html(Runtime.render_root(id))
      assert out =~ "<li>item:a</li><li>item:b</li><li>item:c</li>"
    end
  end

  describe "auto-escaping" do
    test "{expr} text interpolation HTML-escapes its value by default" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      out = html(Runtime.render_root(id))
      assert out =~ "<span id=\"escaped\">&lt;script&gt;alert(1)&lt;/script&gt;</span>"
      refute out =~ "<script>alert(1)</script>"
    end
  end

  describe "attributes" do
    test "string-literal attrs and expression attrs both work on the same tag" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      out = html(Runtime.render_root(id))
      assert out =~ ~s(class="sink")
    end

    test "data-* attrs are routed into the element's generic data_fields, string and expr forms both" do
      defmodule DataAttrs do
        use Nitro.Live

        def render(_assigns) do
          ~H"""
          <div data-testid="root" data-count={1 + 1}><span data-empty>hi</span></div>
          """
        end

        def handle_event(_e, _p, s), do: s
      end

      out = DataAttrs.render(%{}) |> :wf_render.render() |> IO.iodata_to_binary()
      assert out =~ ~s(data-testid="root")
      assert out =~ ~s(data-count="2")
      assert out =~ ~s(data-empty="true")
    end
  end

  describe "raw-text elements (<script>/<style>)" do
    defmodule RawText do
      use Nitro.Live

      def render(_assigns) do
        ~H"""
        <div>
          <script>if (a < b && x > 1) { console.log("{not an expr}"); }</script>
          <style>.foo { color: red; } .bar > .baz { margin: 0; }</style>
          <p>ordinary text still {1 + 1}</p>
        </div>
        """
      end

      def handle_event(_e, _p, s), do: s
    end

    test "<script> content is passed through verbatim -- no nested-tag parsing, no {expr} interpolation" do
      out = RawText.render(%{}) |> :wf_render.render() |> IO.iodata_to_binary()
      assert out =~ "<script>if (a < b && x > 1) { console.log(\"{not an expr}\"); }</script>"
    end

    test "<style> content is passed through verbatim too" do
      out = RawText.render(%{}) |> :wf_render.render() |> IO.iodata_to_binary()
      assert out =~ "<style>.foo { color: red; } .bar > .baz { margin: 0; }</style>"
    end

    test "an ordinary tag right after a raw-text one still interpolates and escapes normally" do
      out = RawText.render(%{}) |> :wf_render.render() |> IO.iodata_to_binary()
      assert out =~ "<p>ordinary text still 2</p>"
    end

    test "an unterminated <script> raises a clear compile error, not a silent bad render" do
      assert_raise RuntimeError, ~r/unterminated <script>/, fn ->
        Code.compile_string("""
        defmodule Nitro.Live.HTMLTest.BadScript do
          use Nitro.Live
          def render(_assigns) do
            ~H"<div><script>if (a < b) {}</div>"
          end
          def handle_event(_e, _p, s), do: s
        end
        """)
      end
    end
  end

  describe "embedding a live component via {expr}" do
    test "a component embedded with {Runtime.component(...)} is a real, independently addressable component" do
      id = uid("sink")
      Runtime.mount(HeexKitchenSink, id)
      child_id = id <> "-child"

      out = html(Runtime.render_root(id))
      assert out =~ "<div id=\"#{child_id}\">"
      assert out =~ ">on</button>"

      # dispatching to the child patches only the child's own subtree
      assert {:changed, child_tree} = Runtime.dispatch(child_id, :flip, %{})
      child_html = html(child_tree)
      assert child_html =~ "<div id=\"#{child_id}\">"
      assert child_html =~ ">off</button>"

      # parent re-render doesn't reset the child's flipped state
      assert html(Runtime.render_root(id)) =~ ">off</button>"
    end
  end

  describe "~H and hand-written NITRO.panel(...) trees interoperate" do
    test "a ~H template can embed a plain nitro record tree, and vice versa" do
      defmodule MixedStyle do
        use Nitro.Live
        require NITRO

        @impl true
        def render(_assigns) do
          NITRO.panel(
            body: [
              ~H"<span>heex child inside a hand-written tree</span>"
            ]
          )
        end

        @impl true
        def handle_event(_event, _params, socket), do: socket
      end

      id = uid("mixed")
      Runtime.mount(MixedStyle, id)
      assert html(Runtime.render_root(id)) ==
               "<div id=\"#{id}\"><div><span>heex child inside a hand-written tree</span></div></div>"
    end
  end

  describe "compile errors" do
    test "a mismatched closing tag raises at compile time, not a silent bad render" do
      assert_raise RuntimeError, ~r/mismatched closing tag/, fn ->
        Code.compile_string("""
        defmodule Nitro.Live.HTMLTest.BadTemplate1 do
          use Nitro.Live
          def render(assigns) do
            ~H"<div><span>oops</div></span>"
          end
          def handle_event(_e, _p, s), do: s
        end
        """)
      end
    end

    test "an unterminated tag raises at compile time" do
      assert_raise RuntimeError, ~r/unterminated/, fn ->
        Code.compile_string("""
        defmodule Nitro.Live.HTMLTest.BadTemplate2 do
          use Nitro.Live
          def render(assigns) do
            ~H'<div class={"x"}'
          end
          def handle_event(_e, _p, s), do: s
        end
        """)
      end
    end
  end
end
