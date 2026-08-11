defmodule Nitro.Live.Socket do
  @moduledoc """
  Assign-holding struct passed through mount/2, render/1 and handle_event/3,
  mirroring Phoenix.LiveView.Socket for the nitro tag/record render pipeline.
  """

  defstruct [:id, :module, assigns: %{}]

  @type t :: %__MODULE__{id: term, module: module, assigns: map}

  def assign(%__MODULE__{assigns: assigns} = socket, key, value) do
    %{socket | assigns: Map.put(assigns, key, value)}
  end

  def assign(%__MODULE__{assigns: assigns} = socket, changes) do
    %{socket | assigns: Enum.into(changes, assigns)}
  end
end
