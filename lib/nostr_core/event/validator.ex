defmodule NostrCore.Event.Validator do
  @moduledoc """
  Internal module for validating event IDs and Schnorr signatures.

  Used by `NostrCore.Event.parse/1` and `NostrCore.Event.valid?/1`.
  """

  alias NostrCore.Event

  @type reason ::
          :missing_created_at
          | :missing_id
          | :missing_signature
          | :missing_pubkey
          | :invalid_id
          | :invalid_signature

  @doc """
  Validate that an event's ID matches its SHA256 serialization and that its
  Schnorr signature is valid for its pubkey.
  """
  @spec validate(Event.t()) :: :ok | {:error, reason()}
  def validate(%Event{created_at: nil}), do: {:error, :missing_created_at}
  def validate(%Event{id: nil}), do: {:error, :missing_id}
  def validate(%Event{sig: nil}), do: {:error, :missing_signature}
  def validate(%Event{pubkey: nil}), do: {:error, :missing_pubkey}

  def validate(%Event{} = event) do
    with :ok <- validate_id(event),
         :ok <- validate_sig(event) do
      :ok
    end
  end

  @doc """
  Returns `true` if the event's ID and signature are valid.
  """
  @spec valid?(Event.t()) :: boolean()
  def valid?(%Event{} = event), do: validate(event) == :ok

  defp validate_id(%Event{id: id} = event) do
    if Event.compute_id(event) == id, do: :ok, else: {:error, :invalid_id}
  rescue
    _ -> {:error, :invalid_id}
  end

  defp validate_sig(%Event{id: id, sig: sig, pubkey: pubkey}) do
    if NostrCore.Crypto.verify?(sig, id, pubkey),
      do: :ok,
      else: {:error, :invalid_signature}
  rescue
    _ -> {:error, :invalid_signature}
  end
end
