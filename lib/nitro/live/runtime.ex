defmodule Nitro.Live.Runtime do
  @moduledoc """
  Per-process live socket registry (process dictionary, same pattern nitro
  itself uses for `nitro:state/1,2` and N2O uses for `#cx{}` -- valid because
  a websocket connection's protocol loop runs in one long-lived process for
  its whole lifetime, so `Process.get/put` behaves like per-connection state).

  Not a supervised GenServer on purpose: this mirrors nitro_pi/n2o_pi's own
  choice to avoid an extra process per stateful thing when the enclosing
  connection process already is one.

  Socket state also mirrors into an ETS-backed cache (`:n2o.cache/3`, the
  same table N2O's own `n2o_pi`/`nitro_pi` use for process handles) keyed by
  `{session_id, live_id}`, when a session id is known -- see `mount/4`. That
  makes a reconnect (page refresh, network blip: a brand new connection
  process, but the same N2O session) restore prior state instead of
  remounting from scratch, as long as N2O reuses the session id, which it
  does whenever the client still holds its `X-Auth-Token` cookie/token.
  """

  require Logger
  alias Nitro.Live.Socket

  require NITRO

  @session_key {__MODULE__, :session_id}
  @stack_key {__MODULE__, :render_stack}
  @cache_table :caching

  @doc """
  Mounts (or, if a persisted socket exists for this session + id, restores)
  `module` under `id`.

  Pass `session_id` (see `Nitro.Live.Examples.Simple.Page` for how to read it off
  the N2O `#cx{}`) so state survives a reconnect; omit it (e.g. in a script
  with no real N2O connection) and this behaves exactly as before --
  process-local only, always mounts fresh.
  """
  def mount(module, id, params \\ %{}, session_id \\ nil) do
    if session_id, do: Process.put(@session_key, session_id)
    mount_or_restore(module, id, params)
  end

  @doc "Renders the current socket for `id`, wrapped in an id-carrying container."
  def render_root(id) do
    socket = fetch_socket!(id)
    render_scoped(socket)
  end

  @doc """
  Embeds a child component from inside a parent's `render/1`.

  Mounts `module` under `id` the first time it's seen (or restores it from
  the persisted cache on a reconnect); on every later call (i.e. every
  subsequent parent re-render) it keeps the component's own accumulated
  state as-is, only calling the component's optional `update/2` to let the
  parent push new params down (Phoenix's LiveComponent default: no
  `update/2` means the parent's params are ignored after mount, the
  component fully owns its state from then on).

  Returns the child's rendered, id-wrapped tree -- nest it directly inside
  the parent's own tree, no special-casing needed in the render pipeline,
  it's just more nitro records. Because the wrapper carries the child's own
  `id`, a click inside it dispatches and patches *only* that id/subtree
  (see `dispatch/3`, `push_patch/2`) even though it renders inline as part
  of the parent.

  A component not called from *any* render pass of its parent for one full
  render (e.g. an `if` in the parent's `render/1` stopped embedding it) is
  torn down: its socket is deleted, both locally and from the persisted
  cache, and so is anything nested under it -- see `render_scoped/1`.
  """
  def component(module, id, params \\ %{}) do
    register_as_child(id)

    socket =
      case Process.get({__MODULE__, id}) do
        nil -> mount_or_restore(module, id, params)
        existing -> update_component(existing, params)
      end

    render_scoped(socket)
  end

  @doc """
  Routes a decoded `{:live_event, id, event, params}` postback to the live
  module's handle_event/3, then diffs old vs new assigns.

  Returns `:unchanged` when the event didn't touch any assign (no re-render,
  no patch sent -- this is the change-tracking LiveView is built around) or
  `{:changed, tree}` with the freshly rendered subtree otherwise. Call
  `push_patch/2` on the `{:changed, tree}` pair from real request code to
  wire it onto the client for an in-place DOM patch.

  A crash in `handle_event/3` or in the `render/1` it triggers is caught
  here, logged with the id/event/params that caused it, and treated as
  `:unchanged` -- the socket is left exactly as it was before the crashing
  event, so one bad event can't corrupt live state or take the connection
  down (N2O's own `nitro_n2o:render_ev/4` already catches exceptions one
  layer up, but only logs a bare stacktrace with no idea which live id or
  event was involved, and would otherwise let a partial/crashed render
  reach `push_patch/2`).
  """
  def dispatch(id, event, params) do
    socket = fetch_socket!(id)

    try do
      new_socket = socket.module.handle_event(event, params, socket)
      put_socket(new_socket)

      if new_socket.assigns == socket.assigns do
        :unchanged
      else
        {:changed, render_scoped(new_socket)}
      end
    rescue
      error ->
        Logger.error(
          "Nitro.Live.Runtime: handle_event/render crashed id=#{inspect(id)} " <>
            "event=#{inspect(event)} params=#{inspect(params)}\n" <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        :unchanged
    end
  end

  @doc """
  Renders `tree` to HTML and wires a call to the client-side `NitroLive.patch/2`
  (see `priv/static/nitro-live.js`), which morphdom-diffs it into the live DOM
  in place -- instead of `nitro:update/2`'s full `outerHTML` replace, this
  preserves node identity, focus and in-progress typing on unrelated/unchanged
  parts of the subtree. Requires a request/N2O context (`get(context)`) to be
  present in the current process, same as `nitro:update/2`.

  The HTML is `nitro:jse/1`-escaped and placed inside a *double-quoted* JS
  string, not a template literal -- unlike `nitro:update/2`'s own `` `~s` ``,
  this means a `${...}` sequence inside rendered content can't be interpreted
  as a JS expression.

  Ordering matters here and is easy to get backwards: rendering `tree` is
  what queues each button's own `qi(id) && qi(id).addEventListener(...)`
  wire action (see element_button.erl) -- but those `id`s don't exist in the
  DOM yet, `NitroLive.patch/2` is what creates them. Queue the patch *before*
  the bindings captured from rendering, so the eval'd script creates the
  nodes first and only then binds listeners onto them; wired in the wrong
  order, `qi(id)` returns null for every binding and clicks silently do
  nothing.
  """
  def push_patch(id, tree) do
    before = actions_list()
    :nitro.actions([])
    html = tree |> :wf_render.render() |> :erlang.iolist_to_binary()
    bindings = actions_list()
    :nitro.actions(before)

    escaped = :nitro.jse(html)
    :nitro.wire(:nitro.f(~c'NitroLive.patch("~s", "~s");', [to_id(id), escaped]))
    :nitro.actions(actions_list() ++ bindings)
  end

  defp actions_list do
    case :nitro.actions() do
      :undefined -> []
      list -> list
    end
  end

  @doc "Pushes a rendered tree as a full outerHTML replace over the live socket's wire. Kept for comparison/fallback -- prefer `push_patch/2`."
  def push_update(id, tree), do: :nitro.update(to_id(id), tree)

  defp mount_or_restore(module, id, params) do
    case restore(id) do
      {:ok, socket} ->
        put_socket(socket)
        socket

      :not_found ->
        socket = %Socket{id: id, module: module, assigns: %{live_id: id}}
        socket = module.mount(params, socket)
        put_socket(socket)
        socket
    end
  end

  # Renders `socket`, tracking which child ids get embedded via `component/3`
  # during this render so any previously-known child NOT seen this time gets
  # torn down -- the same "reconciliation" idea Phoenix's LiveComponent
  # lifecycle uses to garbage-collect components an `if`/`case` in the
  # parent's render/1 stopped rendering.
  defp render_scoped(%Socket{module: module, assigns: assigns, id: id}) do
    parent_stack = Process.get(@stack_key, [])
    Process.put(@stack_key, [id | parent_stack])
    Process.put({:nitro_live_seen, id}, MapSet.new())

    tree = NITRO.panel(id: to_id(id), body: List.wrap(module.render(assigns)))

    seen = Process.get({:nitro_live_seen, id}, MapSet.new())
    Process.delete({:nitro_live_seen, id})
    gc_stale_children(id, seen)
    Process.put(@stack_key, parent_stack)

    tree
  end

  defp register_as_child(child_id) do
    case Process.get(@stack_key, []) do
      [parent | _] ->
        key = {:nitro_live_seen, parent}
        Process.put(key, MapSet.put(Process.get(key, MapSet.new()), child_id))

      [] ->
        :ok
    end
  end

  defp gc_stale_children(parent_id, seen) do
    known_key = {:nitro_live_children, parent_id}
    known = Process.get(known_key, MapSet.new())
    stale = MapSet.difference(known, seen)
    Enum.each(stale, &unmount/1)
    Process.put(known_key, seen)
  end

  defp unmount(id) do
    Enum.each(Process.get({:nitro_live_children, id}, MapSet.new()), &unmount/1)
    Process.delete({:nitro_live_children, id})
    Process.delete({__MODULE__, id})
    depersist(id)
  end

  defp update_component(%Socket{module: module} = socket, params) do
    socket = if function_exported?(module, :update, 2), do: module.update(params, socket), else: socket
    put_socket(socket)
    socket
  end

  defp put_socket(%Socket{id: id} = socket) do
    Process.put({__MODULE__, id}, socket)
    persist(socket)
  end

  defp fetch_socket!(id) do
    case Process.get({__MODULE__, id}) do
      nil -> raise "Nitro.Live.Runtime: no socket mounted for #{inspect(id)}"
      socket -> socket
    end
  end

  defp restore(id) do
    with session_id when not is_nil(session_id) <- Process.get(@session_key),
         socket = %Socket{} <- :n2o.cache(@cache_table, cache_key(session_id, id)) do
      {:ok, socket}
    else
      _ -> :not_found
    end
  end

  defp persist(%Socket{id: id} = socket) do
    case Process.get(@session_key) do
      nil -> :ok
      session_id -> :n2o.cache(@cache_table, cache_key(session_id, id), socket)
    end
  end

  defp depersist(id) do
    case Process.get(@session_key) do
      nil -> :ok
      session_id -> :n2o.cache(@cache_table, cache_key(session_id, id), :undefined)
    end
  end

  defp cache_key(session_id, id), do: {:nitro_live, session_id, id}

  defp to_id(id) when is_binary(id), do: to_charlist(id)
  defp to_id(id), do: id
end
