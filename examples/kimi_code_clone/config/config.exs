import Config

config :kimi_code_clone,
  model: System.get_env("MODEL") || "gpt-4o-mini",
  base_url: System.get_env("BASE_URL") || "https://api.openai.com/v1",
  api_key: System.get_env("OPENAI_API_KEY")
