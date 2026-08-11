defmodule Nitro.Live.HTML.Compiler do
  @moduledoc """
  Compiles a HEEx-flavored template string into Elixir AST that builds the
  same nitro record tree hand-written `NITRO.panel(...)` calls do -- this is
  purely alternate authoring syntax over the exact same render pipeline
  (postback wiring, `Runtime.component/3`, `push_patch/2`'s morphdom diff
  all apply unchanged; a `~H` template and a hand-built tree can nest
  inside each other freely).

  Grammar (intentionally a small subset of real HEEx, not full HTML5):

      template  := node*
      node      := element | text | "{" expr "}"
      element   := "<" tag attr* (">" node* "</" tag ">" | "/>")
      attr      := name "=" ("\"" literal "\"" | "{" expr "}") | name
      directive := ":if" "=" "{" expr "}"  |  ":for" "=" "{" pattern "<-" expr "}"

  Not supported: HTML comments, `<script>`/`<style>` raw-text parsing,
  `data-*`-style hyphenated attributes (nitro records don't have matching
  field names for those), balanced-brace detection inside a nested string
  literal that itself contains `}` (e.g. `{foo("}")}`  will mis-parse).
  These are real, documented limitations of a hand-rolled parser, not
  landmines -- a template hitting one raises a clear `CompileError` at the
  offending point, not a silent wrong render.

  `{expr}` in text position auto-escapes via `NITRO.literal/1`'s default
  `html_encode: true` (mirrors HEEx's own auto-escaping) *unless* the
  expression evaluates to something that already looks like a rendered
  nitro node/list of nodes (a tuple or a list), in which case it's spliced
  through as-is -- see `Nitro.Live.HTML.embed/1`. That's what lets
  `{Runtime.component(Toggle, "id", %{})}` work inline without a special
  component-tag syntax.
  """

  @tag_map %{
    "div" => :panel,
    "a" => :link,
    "img" => :image
  }

  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)

  def compile(source, caller) do
    {nodes, rest} = parse_nodes(String.trim(source), [], nil)

    if rest != "" do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description: "Nitro.Live.HTML: unexpected trailing content: #{inspect(String.slice(rest, 0, 40))}"
    end

    case Enum.map(nodes, &to_ast(&1, caller)) do
      [single] -> single
      many -> many
    end
  end

  # -- parsing ---------------------------------------------------------------

  defp parse_nodes("", acc, nil), do: {Enum.reverse(acc), ""}

  defp parse_nodes("", _acc, close_tag) do
    raise "Nitro.Live.HTML: unexpected end of template, still inside <#{close_tag}>"
  end

  defp parse_nodes(<<"</", rest::binary>>, acc, close_tag) do
    {tag, after_name} = take_name(rest)
    after_gt = skip_to_gt!(after_name, tag)

    if tag != close_tag do
      raise "Nitro.Live.HTML: mismatched closing tag -- expected </#{close_tag}>, got </#{tag}>"
    end

    {Enum.reverse(acc), after_gt}
  end

  defp parse_nodes(<<"<", rest::binary>>, acc, close_tag) do
    {tag, attrs, self_closing?, after_open} = parse_open_tag(rest)

    if self_closing? or tag in @void_tags do
      parse_nodes(after_open, [{:tag, tag, attrs, []} | acc], close_tag)
    else
      {children, after_children} = parse_nodes(after_open, [], tag)
      parse_nodes(after_children, [{:tag, tag, attrs, children} | acc], close_tag)
    end
  end

  defp parse_nodes(<<"{", rest::binary>>, acc, close_tag) do
    {expr_src, after_expr} = take_balanced(rest, 1, [])
    parse_nodes(after_expr, [{:expr, expr_src} | acc], close_tag)
  end

  defp parse_nodes(input, acc, close_tag) do
    {text, rest} = take_text(input, [])
    parse_nodes(rest, [{:text, text} | acc], close_tag)
  end

  defp take_text(<<c, _::binary>> = input, acc) when c in [?<, ?{] do
    {IO.iodata_to_binary(Enum.reverse(acc)), input}
  end

  defp take_text(<<c::utf8, rest::binary>>, acc), do: take_text(rest, [<<c::utf8>> | acc])
  defp take_text("", acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp take_balanced(<<"}", rest::binary>>, 1, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp take_balanced(<<"}", rest::binary>>, depth, acc), do: take_balanced(rest, depth - 1, ["}" | acc])
  defp take_balanced(<<"{", rest::binary>>, depth, acc), do: take_balanced(rest, depth + 1, ["{" | acc])
  defp take_balanced(<<c::utf8, rest::binary>>, depth, acc), do: take_balanced(rest, depth, [<<c::utf8>> | acc])
  defp take_balanced("", _depth, _acc), do: raise("Nitro.Live.HTML: unterminated { expression }")

  defp parse_open_tag(input) do
    {tag, rest} = take_name(input)
    parse_attrs(skip_whitespace(rest), tag, [])
  end

  defp parse_attrs(<<"/>", rest::binary>>, tag, acc), do: {tag, Enum.reverse(acc), true, rest}
  defp parse_attrs(<<">", rest::binary>>, tag, acc), do: {tag, Enum.reverse(acc), false, rest}
  defp parse_attrs("", tag, _acc), do: raise("Nitro.Live.HTML: unterminated <#{tag} ...> tag")

  defp parse_attrs(input, tag, acc) do
    {attr, rest} = parse_attr(input)
    parse_attrs(skip_whitespace(rest), tag, [attr | acc])
  end

  defp parse_attr(input) do
    {name, rest} = take_attr_name(input)
    rest = skip_whitespace(rest)

    case rest do
      <<"=", rest2::binary>> ->
        rest2 = skip_whitespace(rest2)

        case rest2 do
          <<"\"", rest3::binary>> ->
            {value, rest4} = take_until_quote(rest3, [])
            {{name, {:string, value}}, rest4}

          <<"{", rest3::binary>> ->
            {expr_src, rest4} = take_balanced(rest3, 1, [])
            {{name, {:expr, expr_src}}, rest4}

          _ ->
            raise "Nitro.Live.HTML: attribute #{name}= must be followed by \"...\" or {...}"
        end

      _ ->
        {{name, {:expr, "true"}}, rest}
    end
  end

  defp take_until_quote(<<"\"", rest::binary>>, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp take_until_quote(<<c::utf8, rest::binary>>, acc), do: take_until_quote(rest, [<<c::utf8>> | acc])
  defp take_until_quote("", _acc), do: raise("Nitro.Live.HTML: unterminated attribute value")

  defp take_name(input) do
    case Regex.run(~r/\A([a-zA-Z][a-zA-Z0-9_.]*)/, input) do
      [match, name] -> {name, binary_part(input, byte_size(match), byte_size(input) - byte_size(match))}
      nil -> raise "Nitro.Live.HTML: expected a tag name, got: #{inspect(String.slice(input, 0, 20))}"
    end
  end

  defp take_attr_name(input) do
    case Regex.run(~r/\A([a-zA-Z:][a-zA-Z0-9_\-:]*)/, input) do
      [match, name] -> {name, binary_part(input, byte_size(match), byte_size(input) - byte_size(match))}
      nil -> raise "Nitro.Live.HTML: expected an attribute name, got: #{inspect(String.slice(input, 0, 20))}"
    end
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_whitespace(rest)
  defp skip_whitespace(input), do: input

  defp skip_to_gt!(<<">", rest::binary>>, _tag), do: rest
  defp skip_to_gt!(<<c, rest::binary>>, tag) when c in [?\s, ?\t, ?\n, ?\r], do: skip_to_gt!(rest, tag)
  defp skip_to_gt!("", tag), do: raise("Nitro.Live.HTML: unterminated </#{tag}>")
  defp skip_to_gt!(other, tag), do: raise("Nitro.Live.HTML: unexpected content in </#{tag} ...>: #{inspect(String.slice(other, 0, 20))}")

  # -- codegen -----------------------------------------------------------

  defp to_ast({:text, text}, _caller) do
    # nitro:html_encode/1 (called by element_literal.erl) only has clauses
    # for charlists, not Elixir binaries -- to_charlist/1 here (not in
    # generated code) since `text` is already known at compile time.
    quote do: NITRO.literal(body: unquote(String.to_charlist(text)))
  end

  defp to_ast({:expr, src}, caller) do
    ast = parse_expr!(src, caller)
    quote do: Nitro.Live.HTML.embed(unquote(ast))
  end

  defp to_ast({:tag, tag, attrs, children}, caller) do
    {for_clause, attrs} = pop_directive(attrs, ":for")
    {if_expr, attrs} = pop_directive(attrs, ":if")

    node_ast = build_node_ast(tag, attrs, children, caller)
    node_ast = wrap_if(node_ast, if_expr, caller)
    wrap_for(node_ast, for_clause, caller)
  end

  defp build_node_ast(tag, attrs, children, caller) do
    attrs_ast = Enum.map(attrs, &attr_to_ast(&1, caller))
    children_ast = Enum.map(children, &to_ast(&1, caller))
    body_ast = quote do: List.flatten(unquote(children_ast))

    # Record macros require their argument to *look like* a literal keyword
    # list at the AST level (values may be arbitrary expressions, but the
    # `[key: val, ...]` shape itself must be visible at compile time) -- so
    # this concatenation has to happen here, in the compiler, not as a
    # generated runtime `++` call, or NITRO.span/1 etc. reject it.
    full_kw_ast = attrs_ast ++ [{:body, body_ast}]

    case Map.get(@tag_map, tag, tag_to_atom(tag)) do
      nil -> quote do: NITRO.element(unquote([{:html_tag, tag} | full_kw_ast]))
      atom -> quote do: NITRO.unquote(atom)(unquote(full_kw_ast))
    end
  end

  # Only ever dispatches to NITRO record macros that genuinely exist --
  # falls back to the generic `#element{}` (nil) for anything not in this
  # fixed, hand-picked list, rather than guessing at arbitrary tag names.
  @known_tags ~w(span p pre hr br blockquote code mark button form label
                 select option optgroup textarea input table tr td th
                 thead tbody tfoot caption colgroup col ul ol li dl dt dd
                 h1 h2 h3 h4 h5 h6 header footer nav section article aside
                 main body head title meta style script
                 fieldset legend output progress meter details summary)
                |> Enum.into(MapSet.new())

  defp tag_to_atom(tag) do
    if MapSet.member?(@known_tags, tag), do: String.to_atom(tag)
  end

  defp attr_to_ast({name, {:string, value}}, _caller), do: {attr_atom(name), value}
  defp attr_to_ast({name, {:expr, src}}, caller), do: {attr_atom(name), parse_expr!(src, caller)}

  defp attr_atom(name), do: String.to_atom(name)

  defp pop_directive(attrs, directive_name) do
    case Enum.split_with(attrs, fn {name, _} -> name == directive_name end) do
      {[], rest} -> {nil, rest}
      {[{^directive_name, {:expr, src}}], rest} -> {src, rest}
      {[{^directive_name, {:string, _}}], _rest} -> raise "Nitro.Live.HTML: #{directive_name} must be #{directive_name}={...}, not a string literal"
    end
  end

  defp wrap_if(node_ast, nil, _caller), do: node_ast

  defp wrap_if(node_ast, expr_src, caller) do
    cond_ast = parse_expr!(expr_src, caller)
    quote do: if(unquote(cond_ast), do: unquote(node_ast), else: nil)
  end

  defp wrap_for(node_ast, nil, _caller), do: node_ast

  defp wrap_for(node_ast, clause_src, caller) do
    {:<-, _, [pattern, enumerable]} = parse_expr!(clause_src, caller)
    quote do: (for unquote(pattern) <- unquote(enumerable), do: unquote(node_ast))
  end

  defp parse_expr!(src, caller) do
    src
    |> Code.string_to_quoted!(file: caller.file, line: caller.line)
    |> expand_assigns()
  end

  # `@name` inside a template expression means "read this assign", not "read
  # a module attribute" -- same rewrite Phoenix.Component does for HEEx.
  defp expand_assigns(ast) do
    Macro.prewalk(ast, fn
      {:@, _, [{name, _, ctx}]} when is_atom(name) and is_atom(ctx) ->
        quote do: Map.fetch!(var!(assigns), unquote(name))

      other ->
        other
    end)
  end
end
