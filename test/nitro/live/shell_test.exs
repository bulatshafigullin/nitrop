defmodule Nitro.Live.ShellTest do
  use ExUnit.Case, async: true

  alias Nitro.Live.Shell

  test "render/1 replaces the %%WS_PATH%% marker with the given path" do
    html = Shell.render("/ws")
    assert html =~ ~s(wsPath = "/ws";)
    refute html =~ "%%WS_PATH%%"
  end

  test "render/1 with a non-default path templates that in instead" do
    html = Shell.render("/live-ws")
    assert html =~ ~s(wsPath = "/live-ws";)
    refute html =~ ~s(wsPath = "/ws";)
  end

  test "the rest of the shell (root div, script tags) is untouched" do
    html = Shell.render("/ws")
    assert html =~ ~s(<div id="root">)
    assert html =~ "/static/vendor/n2o/n2o.js"
    assert html =~ "N2O_start();"
  end
end
