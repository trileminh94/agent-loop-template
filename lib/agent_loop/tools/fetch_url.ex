defmodule AgentLoop.Tools.FetchURL do
  @moduledoc """
  Fetch a URL and return its text content.

  Uses `Req` (already a dependency of the example provider). HTML pages are
  stripped to readable text when possible.
  """

  @behaviour AgentLoop.Tool

  @impl true
  def name, do: "fetch_url"

  @impl true
  def description do
    "Fetch a URL and return its text content. Use this to read documentation or web pages."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "description" => "URL to fetch"
        }
      },
      "required" => ["url"]
    }
  end

  @impl true
  def execute(args) do
    url = Map.get(args, "url")

    if is_nil(url) or url == "" do
      {:error, "missing required argument: url"}
    else
      case URI.parse(url) do
        %URI{scheme: scheme} when scheme in ["http", "https"] ->
          do_fetch(url)

        _ ->
          {:error, "invalid URL: #{url}"}
      end
    end
  end

  defp do_fetch(url) do
    case Req.get(url, receive_timeout: 30_000, redirect: true) do
      {:ok, %{status: status, body: body, headers: headers}} when status in 200..299 ->
        content_type = content_type(headers)
        text = extract_text(body, content_type)
        {:ok, String.slice(text, 0, 50_000)}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{String.slice(body, 0, 500)}"}

      {:error, reason} ->
        {:error, "request failed: #{inspect(reason)}"}
    end
  end

  defp content_type(headers) do
    headers
    |> Enum.find_value("", fn {k, v} ->
      if String.downcase(k) == "content-type", do: List.first(v, ""), else: nil
    end)
    |> String.downcase()
  end

  defp extract_text(body, content_type) when is_binary(body) do
    if String.contains?(content_type, "html") do
      body
      |> strip_tags()
      |> collapse_whitespace()
    else
      body
    end
  end

  defp extract_text(body, _content_type), do: inspect(body)

  defp strip_tags(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, " ")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, " ")
    |> String.replace(~r/<[^>]+>/, " ")
  end

  defp collapse_whitespace(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
