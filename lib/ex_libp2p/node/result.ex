defmodule ExLibp2p.Node.Result do
  @moduledoc false
  # Internal helpers shared by Node and its Ops modules. Two distinct concerns:
  #   * `normalize_ok/1` collapses `{:ok, true}` from fire-and-forget NIF calls
  #     to bare `:ok` for Elixir callers.
  #   * `tag/1` extracts the success/failure flavour for telemetry metadata.

  @type call_result :: :ok | {:ok, term()} | {:error, term()} | term()

  @doc """
  Normalizes a NIF fire-and-forget result.

  NIF commands return `{:ok, true} | {:error, reason}`. Elixir callers expect
  `:ok | {:error, reason}`. This collapses the success arm.
  """
  @spec normalize_ok(call_result()) :: call_result()
  def normalize_ok({:ok, _}), do: :ok
  def normalize_ok({:error, _} = err), do: err
  def normalize_ok(other), do: other

  @doc """
  Tags a result for telemetry: `:ok | :error | :unknown`.

  Used as the `:result` metadata key in `:telemetry.span/3` measurements.
  """
  @spec tag(call_result()) :: :ok | :error | :unknown
  def tag(:ok), do: :ok
  def tag({:ok, _}), do: :ok
  def tag({:error, _}), do: :error
  def tag(_), do: :unknown
end
