defmodule Nitro.Live.Reload do
  @moduledoc """
  Dev-only auto-reload: watches a directory via `synrc/fs`'s native OS
  file watcher (fsevent on Mac, inotify on Linux, inotify-win on Windows --
  see its own README) and, on any `.ex`/`.exs` file change, recompiles it
  (`Code.compile_file/1` -- a real Erlang hot code swap, the running VM
  starts using the new module version for anything called after the
  compile finishes, no restart) and tells every currently-connected
  browser that opted in to reload the page.

  Deliberately doesn't try to be smarter than a full page reload -- no
  attempt to preserve a Live module's state across ITS OWN code changing
  (the old socket's assigns may not even make sense under the new code).
  Same trade-off Phoenix's code reloader and most JS dev servers make:
  correctness over continuity for a rare, dev-only event.

  Three pieces, all opt-in:

  1. `start/1` -- call once from dev-only startup code (a dev script, not
     `Server.start/1` itself: `fs` is a native OS-level dependency with
     nothing to do with what a demo server needs to actually serve
     requests, hence `only: :dev` in `mix.exs`).
  2. `watch/0` -- call from a page module's `event(:init)` to opt THAT
     connection into reload notifications. A safe no-op if `start/1` was
     never called (production / no dev tooling) -- checks the registry
     exists first rather than crashing when it doesn't.
  3. `Nitro.Live.Reload.Protocol` -- add to
     `Application.put_env(:n2o, :protocols, [...])` for a `watch/0`'d
     connection to actually receive the reload command; without it in the
     list, same as `Nitro.Live.PubSub.Protocol`, nothing errors, the
     signal just never reaches a browser.

  Built on the exact same `Registry`-based fan-out `Nitro.Live.PubSub`
  uses, kept as an entirely separate registry/topic on purpose: reload is
  a single fixed, code-level signal with no per-app topic or payload, not
  a general pub/sub channel apps route their own messages through.
  """

  # :fs is `only: :dev` in mix.exs (a native OS-level dep with nothing to
  # do with test/prod) -- not compiled/available in other envs, so the
  # compiler can't see :fs.start_link/2 or :fs.subscribe/1 exist. They do,
  # at runtime, in the only env (:dev) that ever calls start/1.
  @compile {:no_warn_undefined, :fs}

  require Logger

  @registry __MODULE__.Registry
  @fs_name __MODULE__.FS

  @doc "Starts watching `dir` (recursively) for .ex/.exs changes. Call once, from dev tooling only."
  def start(dir \\ "lib") do
    {:ok, _} = Application.ensure_all_started(:fs)
    ensure_registry_started()

    path = dir |> Path.expand() |> to_charlist()
    {:ok, _} = :fs.start_link(@fs_name, path)

    # :fs.subscribe/1 registers self() -- the CALLING process -- as the
    # target for file events (gen_event:add_sup_handler(..., [self()])).
    # It has to run inside the spawned loop/0 process itself, not here:
    # calling it in start/1 would subscribe start/1's OWN caller (some
    # unrelated dev-script process with nothing ever reading its mailbox),
    # leaving loop/0 waiting on a mailbox no event was ever sent to.
    pid =
      spawn_link(fn ->
        :fs.subscribe(@fs_name)
        loop()
      end)

    Logger.info("Nitro.Live.Reload watching #{Path.expand(dir)}")
    {:ok, pid}
  end

  @doc "Opts the current connection into reload notifications. A no-op if start/1 was never called."
  def watch do
    if Process.whereis(@registry), do: Registry.register(@registry, :reload, [])
    :ok
  end

  # Many editors (and this codebase's own Edit tool, confirmed against the
  # real fsevent stream) don't write a file in place -- they write a temp
  # file, then atomically rename it over the target, to avoid a reader
  # ever observing a half-written file. That means the event carrying
  # `:modified` lands on the *temp* file's own (non-.ex) name, and the
  # event on the REAL target path only ever carries `:renamed`, never
  # `:modified` -- a watcher that only reacts to :modified on a .ex path
  # silently never fires for this whole, extremely common write pattern.
  @relevant_events [:modified, :renamed, :created]

  defp loop do
    receive do
      {_pid, {:fs, :file_event}, {path, events}} ->
        path = to_string(path)
        if Path.extname(path) in [".ex", ".exs"] and Enum.any?(events, &(&1 in @relevant_events)) do
          recompile_and_notify(path)
        end

      _other ->
        :ok
    end

    loop()
  end

  defp recompile_and_notify(path) do
    Code.compile_file(path)
    Logger.info("Nitro.Live.Reload: recompiled #{path}, reloading connected browsers")
    notify_all()
  rescue
    error ->
      Logger.error(
        "Nitro.Live.Reload: compile error in #{path}\n" <> Exception.format(:error, error, __STACKTRACE__)
      )
  end

  defp notify_all do
    Registry.dispatch(@registry, :reload, fn entries ->
      for {pid, _} <- entries, do: send(pid, :nitro_live_reload)
    end)
  end

  # Same LINKS-the-caller hazard Nitro.Live.PubSub guards against -- the
  # caller here is dev-startup code rather than a connection process, so
  # it's lower-stakes, but there's no reason to depend on that.
  defp ensure_registry_started do
    case Registry.start_link(keys: :duplicate, name: @registry) do
      {:ok, pid} -> Process.unlink(pid)
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
