import Config

config :pleroma, :frontends,
  primary: %{
    "name" => "mangane",
    "ref" => "dist"
  },
  admin: %{
    "name" => "admin-fe",
    "ref" => "stable"
  }
