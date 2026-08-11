defmodule Nitro.Live.PubSubTest do
  @moduledoc """
  A real cross-connection broadcast needs a SECOND process to prove
  anything -- one process's own `Nitro.Live.Runtime` state (mounted
  sockets, everything `Nitro.Live.PubSub.subscribed_ids/1` reads) lives in
  ITS OWN process dictionary, not the test process's, the same way two
  real browser tabs are two real, separate connection processes. Every
  test here spawns at least one subscriber process for exactly that
  reason.
  """
  use ExUnit.Case, async: true

  alias Nitro.Live.{PubSub, Runtime, Socket}
  alias Nitro.Live.PubSub.Protocol

  defmodule Counter do
    use Nitro.Live
    def mount(_params, socket), do: Socket.assign(socket, :count, 0)
    def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])
    def handle_event(_e, _p, s), do: s
    def handle_info(:increment, socket), do: Socket.assign(socket, :count, socket.assigns.count + 1)
  end

  defmodule NoHandleInfo do
    use Nitro.Live
    def mount(_params, socket), do: Socket.assign(socket, :count, 0)
    def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])
    def handle_event(_e, _p, s), do: s
  end

  defp uid(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp spawn_subscriber(topic, module, id) do
    test_pid = self()

    pid =
      spawn(fn ->
        require N2O
        Process.put(:context, N2O.cx())
        socket = Runtime.mount(module, id)
        PubSub.subscribe(topic, socket)
        send(test_pid, :ready)

        loop = fn loop ->
          receive do
            {:nitro_live_broadcast, _, _} = msg ->
              send(test_pid, {:broadcast_result, Protocol.info(msg, nil, nil)})
              loop.(loop)

            :stop ->
              :ok
          end
        end

        loop.(loop)
      end)

    assert_receive :ready, 500
    pid
  end

  describe "subscribe/2 + broadcast/2 -- across two real processes" do
    test "a broadcast reaches a subscriber in a different process and patches its mounted id" do
      topic = uid("topic")
      id = uid("counter")
      pid = spawn_subscriber(topic, Counter, id)

      PubSub.broadcast(topic, :increment)

      assert_receive {:broadcast_result, {:reply, {:bert, {:io, code, _}}, nil, nil}}, 500
      js = IO.iodata_to_binary(code)
      assert js =~ "NitroLive.patch(\"#{id}\","
      assert js =~ "count=1"

      send(pid, :stop)
    end

    test "a module without handle_info/2 is left alone, no crash, no patch" do
      topic = uid("topic")
      id = uid("counter")
      pid = spawn_subscriber(topic, NoHandleInfo, id)

      PubSub.broadcast(topic, :increment)

      assert_receive {:broadcast_result, {:reply, {:bert, {:io, code, _}}, nil, nil}}, 500
      # io/1 always renders SOMETHING (even if empty) -- the point is it
      # does NOT contain a patch for our id, since dispatch_info/2 was :unchanged.
      refute IO.iodata_to_binary(code) =~ "NitroLive.patch(\"#{id}\","

      send(pid, :stop)
    end

    test "a broadcast to a DIFFERENT topic is not delivered" do
      topic = uid("topic")
      other_topic = uid("other-topic")
      id = uid("counter")
      pid = spawn_subscriber(topic, Counter, id)

      PubSub.broadcast(other_topic, :increment)

      refute_receive {:broadcast_result, _}, 300
      send(pid, :stop)
    end

    test "two ids on the SAME connection subscribed to the SAME topic each get exactly one dispatch per broadcast" do
      topic = uid("topic")
      test_pid = self()

      pid =
        spawn(fn ->
          require N2O
          Process.put(:context, N2O.cx())
          id_a = "a"
          id_b = "b"
          socket_a = Runtime.mount(Counter, id_a)
          socket_b = Runtime.mount(Counter, id_b)
          PubSub.subscribe(topic, socket_a)
          PubSub.subscribe(topic, socket_b)
          send(test_pid, :ready)

          receive do
            {:nitro_live_broadcast, _, _} = msg ->
              send(test_pid, {:broadcast_result, Protocol.info(msg, nil, nil)})
          end
        end)

      assert_receive :ready, 500
      PubSub.broadcast(topic, :increment)

      assert_receive {:broadcast_result, {:reply, {:bert, {:io, code, _}}, nil, nil}}, 500
      js = IO.iodata_to_binary(code)
      # each patch shows count=1, not count=2 -- if Registry delivered the
      # broadcast message twice (the duplicate-registration bug subscribe/2
      # guards against), dispatch_info would have run twice per id.
      assert js =~ "NitroLive.patch(\"a\", \"<div id=\\\"a\\\"><span>count=1</span></div>\")"
      assert js =~ "NitroLive.patch(\"b\", \"<div id=\\\"b\\\"><span>count=1</span></div>\")"

      send(pid, :stop)
    end
  end

  describe "Runtime.dispatch_info/2" do
    test "an id that was never mounted is :unchanged, not a crash" do
      assert Runtime.dispatch_info(uid("nope"), :increment) == :unchanged
    end

    test "a crashing handle_info/2 leaves the socket as-is and returns :unchanged" do
      defmodule CrashOnInfo do
        use Nitro.Live
        def mount(_params, socket), do: Nitro.Live.Socket.assign(socket, :count, 0)
        def render(assigns), do: NITRO.span(body: ["count=#{assigns.count}"])
        def handle_event(_e, _p, s), do: s
        def handle_info(:boom, _socket), do: raise("simulated crash")
      end

      id = uid("crasher")
      require N2O
      Process.put(:context, N2O.cx())
      Runtime.mount(CrashOnInfo, id)
      assert Runtime.dispatch_info(id, :boom) == :unchanged
      assert Runtime.dispatch_info(id, :increment) == :unchanged
    end
  end
end
