defmodule Nitro.Live.ReloadTest do
  @moduledoc """
  Doesn't start the real file watcher (`Nitro.Live.Reload.start/1`) --
  that's a real OS-level fsevent/inotify process, not something to spin up
  and tear down per test run. Covers the two pieces that don't need it:
  `watch/0`'s no-op safety when the watcher was never started (the normal
  case for every OTHER test in this suite, and for a real server not
  running in dev-reload mode), and the wire-JS `Nitro.Live.Reload.Protocol`
  produces, which is exactly what a real file change would trigger.
  """
  use ExUnit.Case, async: true

  alias Nitro.Live.Reload

  describe "watch/0 without start/1 having been called" do
    test "is a safe no-op, not a crash" do
      assert Reload.watch() == :ok
    end
  end

  describe "Reload.Protocol" do
    test "replies with a raw window.location.reload(), not a Nitro.Live patch" do
      assert {:reply, {:bert, {:io, code, _}}, nil, nil} = Reload.Protocol.info(:nitro_live_reload, nil, nil)
      assert IO.iodata_to_binary(code) =~ "window.location.reload();"
    end

    test "anything else is :unknown, so other protocol modules still get a chance" do
      assert Reload.Protocol.info(:something_else, nil, nil) == {:unknown, :something_else, nil, nil}
      assert Reload.Protocol.info({:nitro_live_broadcast, "t", :x}, nil, nil) ==
               {:unknown, {:nitro_live_broadcast, "t", :x}, nil, nil}
    end
  end
end
