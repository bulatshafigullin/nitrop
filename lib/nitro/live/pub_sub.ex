defmodule Nitro.Live.PubSub do
  @moduledoc """
  Cross-connection broadcast -- Phoenix.PubSub's job -- so one connection's
  event can push an update into every OTHER connection watching the same
  topic, not just the one that triggered it. Backed by a plain `Registry`
  (`keys: :duplicate`, one entry per `{topic, subscriber_id}`), not a
  separate pub/sub server: each connection process is already long-lived
  for the life of its WebSocket (see `Nitro.Live.Runtime`'s moduledoc for
  why that's the same reasoning nitro's own primitives rely on), so
  `Registry.dispatch/3` + `send/2` to each subscriber's pid is enough.

  ## How a broadcast actually reaches the browser

  `broadcast/2` sends `{:nitro_live_broadcast, topic, message}` to every
  subscribed pid. Nothing about that is nitro/N2O-specific -- it's plain
  `send/2` -- so it needs a receiving side registered with cowboy's own
  websocket machinery to do anything: `Nitro.Live.PubSub.Protocol` is an
  N2O protocol module (same contract as `n2o_heart`/`nitro_n2o`, see its
  moduledoc) that recognizes that message shape, and must be added to
  the `:protocols` option of `Nitro.Live.Site` (`[..., Nitro.Live.PubSub.Protocol]`)
  for broadcasts to have any effect (see `Simple.Server`) -- subscribing
  without that wired up silently never patches anything.

  ## Wiring up a live view

      def mount(_params, socket) do
        socket = PubSub.subscribe("room:1", socket)
        Socket.assign(socket, :count, 0)
      end

      def handle_event(:increment, _params, socket) do
        PubSub.broadcast("room:1", :increment)
        socket  # unchanged -- the actual update happens in handle_info/2,
                # uniformly for every subscriber including this one
      end

      def handle_info(:increment, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)

  `handle_info/2` is optional, the same way `update/2` is -- see
  `Nitro.Live.Runtime.dispatch_info/2`, which no-ops (not a compile error)
  for a module that doesn't define one.

  ## What this does NOT do

  No "give me the current state on join" -- a connection that subscribes
  after a broadcast already happened just never saw it; unlike Phoenix's
  ecosystem (which pairs PubSub with a separate state store, or Presence,
  for that), nothing here tracks history or canonical state. Fine for
  "notify me of new things from now on" (what `SharedCounter` shows); not
  fine if a late joiner needs to catch up -- that's a different feature.

  Also no cleanup of a topic's subscriber-id list when a *component*
  (as opposed to the whole connection) unmounts: `Registry` itself
  automatically drops an entry when the registering *process* dies (a
  whole connection closing), but a single component id going away via
  `Runtime`'s child GC while the connection stays open leaves its id in
  `subscribed_ids/1`'s bookkeeping -- `Runtime.dispatch_info/2` handles
  that gracefully (treats a since-unmounted id as `:unchanged`, not a
  crash) rather than actually cleaning it up. A real, not just
  theoretical, gap for a component -- as opposed to a whole page -- that
  subscribes and is later unmounted while its connection stays open.
  """

  alias Nitro.Live.Socket

  @registry __MODULE__.Registry

  @doc """
  Subscribes `socket.id` to `topic` -- broadcasts to `topic` will call
  `socket.module`'s `handle_info/2` for this id. Returns `socket`
  unchanged so it composes in a `mount/2` pipe.

  Registers this *process* with `topic` at most once no matter how many
  different ids on this same connection subscribe to it: `Registry`'s
  `:duplicate` keys allow the same process to register a key more than
  once, and `broadcast/2` would then `send/2` this process one message per
  registration -- multiple ids sharing a topic on one connection would
  otherwise see `Runtime.dispatch_info/2` run more than once per
  broadcast.
  """
  def subscribe(topic, %Socket{id: id} = socket) do
    ensure_started()
    if MapSet.size(subscribed_ids(topic)) == 0, do: Registry.register(@registry, topic, [])
    track_id(topic, id)
    socket
  end

  @doc "Broadcasts `message` to every id subscribed to `topic`, across every connection -- including this one, if it's also subscribed."
  def broadcast(topic, message) do
    ensure_started()
    Registry.dispatch(@registry, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:nitro_live_broadcast, topic, message})
    end)

    :ok
  end

  @doc "The ids THIS connection has subscribed to `topic` -- used by `Nitro.Live.PubSub.Protocol` to know which mounted ids to `Runtime.dispatch_info/2` on receipt."
  def subscribed_ids(topic), do: Process.get({__MODULE__, :ids, topic}, MapSet.new())

  defp track_id(topic, id) do
    key = {__MODULE__, :ids, topic}
    Process.put(key, MapSet.put(Process.get(key, MapSet.new()), id))
  end

  # Registry.start_link/1 LINKS the caller -- fine for supervision trees,
  # wrong here: the caller is often a connection process, and a connection
  # closing must not crash the registry every other connection depends on.
  # Started once (idempotently) and immediately unlinked.
  defp ensure_started do
    case Registry.start_link(keys: :duplicate, name: @registry) do
      {:ok, pid} -> Process.unlink(pid)
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
