defmodule PokeAround.Repo do
  use Ecto.Repo,
    otp_app: :poke_around,
    adapter: Ecto.Adapters.Postgres
end
