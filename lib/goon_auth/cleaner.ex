defmodule GoonAuth.Cleaner do
  @moduledoc """
  A process that periodically runs cleanup operations. The current cleanup
  operations are:

  1. Clean up registrations ETS table and remove registrations older than
     5 minutes.
  """
  use GenServer
  require Logger

  def start_link (args) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(integer) :: {:ok, term}
  def init(sec) do
    Logger.info("Starting cleaner process with #{sec}s interval")
    interval = sec * 1000

    :erlang.send_after(interval, self(), :clean)

    {:ok, %{interval: interval}}
  end

  def handle_info(:clean, state) do
    clean_registrations
    :erlang.send_after(state[:interval], self(), :clean)
    {:noreply, state}
  end

  @doc "Cleans up the registrations ETS table"
  def clean_registrations do
    cutoff = :os.system_time(:seconds) - 300

    # We only care about the third value (timestamp)
    match = {:"_", :"_", :"_", :"$1"}
    filter = {:<, :"$1", cutoff}
    pattern = [{match, [filter], [true]}]

    num_deleted = :ets.select_delete(:registrations, pattern)

    if num_deleted > 0 do
      Logger.info("Deleted #{num_deleted} expired registrations")
    end
  end
end
