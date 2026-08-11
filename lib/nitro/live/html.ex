defmodule Nitro.Live.HTML do
  @moduledoc """
  `~H` sigil: an alternate, HEEx-flavored way to build the exact same nitro
  record tree `NITRO.panel(...)`-style calls do. See
  `Nitro.Live.HTML.Compiler` for the grammar and its limitations.

      def render(assigns) do
        ~H\"\"\"
        <div class="counter">
          <span>Count: {@count}</span>
          <button postback={live_event(@live_id, :inc)} delegate={Nitro.Live.Dispatcher}>+</button>
        </div>
        \"\"\"
      end

  Available automatically via `use Nitro.Live`.
  """

  require NITRO

  defmacro sigil_H({:<<>>, _meta, [string]}, _modifiers) when is_binary(string) do
    Nitro.Live.HTML.Compiler.compile(string, __CALLER__)
  end

  @doc """
  Splices a `{expr}` template interpolation's value into a nitro `body:`
  list. A tuple, or a list whose first element is a tuple (or an empty
  list), is assumed to already be a rendered nitro node/nodes (e.g. the
  result of `Runtime.component/3`, or another `~H` call) and passed through
  untouched; anything else is stringified and HTML-escaped via
  `NITRO.literal/1` (`html_encode: true` is its default), mirroring HEEx's
  own auto-escaping of `{expr}` text.

  Stringifies to a charlist, not a binary: `nitro:html_encode/1` (called by
  `element_literal.erl`) only has clauses for charlists -- passing it an
  Elixir string (a UTF-8 binary) raises `FunctionClauseError`.
  """
  def embed(value) when is_tuple(value), do: value
  def embed([]), do: []
  def embed([first | _] = nodes) when is_tuple(first), do: nodes
  def embed(value), do: NITRO.literal(body: to_charlist(value))
end
