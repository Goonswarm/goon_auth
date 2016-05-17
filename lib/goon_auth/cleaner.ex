defmodule GoonAuth.Cleaner do
  @moduledoc """
  A process that periodically runs cleanup operations. The current cleanup
  operations are:

  1. Clean up registrations ETS table and remove registrations older than
     5 minutes.
  """
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(integer) :: {:ok, term}
  def init(sec) do
    Logger.info("Starting cleaner process with #{sec}s interval")
    # timer functions require milliseconds
    interval = sec * 1000

    :erlang.send_after(interval, self(), :clean)

    {:ok, %{interval: interval}}
  end

  @doc "GenServer callback for receiving messages"
  def handle_info(:clean, state) do
    clean_registrations
    :erlang.send_after(state[:interval], self(), :clean)
    {:noreply, state}
  end

  @doc "Cleans up the registrations ETS table."
  def clean_registrations do
    # The registration "cutoff" is 5 minutes before the current time
    cutoff = :os.system_time(:seconds) - 300

    # Build an ETS select filter

    # We only care about the third value (timestamp)
    # Using underscores dismisses other values
    match = {:"_", :"_", :"_", :"$1"}

    # The match above binds the $1 variable, filter syntax is in reverse polish
    # notation :shrug:
    filter = {:<, :"$1", cutoff}

    # Return true for all selects, it's the only accepted value for actually
    # causing a deletion.
    pattern = [{match, [filter], [true]}]

    num_deleted = :ets.select_delete(:registrations, pattern)

    if num_deleted > 0 do
      Logger.info("Deleted #{num_deleted} expired registrations")
    end
  end
end
