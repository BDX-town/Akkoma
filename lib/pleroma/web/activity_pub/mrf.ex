# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF do
  @callback filter(Map.t()) :: {:ok | :reject, Map.t()}

  def filter(policies, %{} = object) do
    policies
    |> Enum.reduce({:ok, object}, fn
      policy, {:ok, object} ->
        policy.filter(object)

      _, error ->
        error
    end)
  end

  def filter(%{} = object), do: get_policies() |> filter(object)

  def get_policies do
    Pleroma.Config.get([:instance, :rewrite_policy], []) |> get_policies()
  end

  defp get_policies(policy) when is_atom(policy), do: [policy]
  defp get_policies(policies) when is_list(policies), do: policies
  defp get_policies(_), do: []

  @spec subdomains_regex([String.t()]) :: [Regex.t()]
  def subdomains_regex(domains) when is_list(domains) do
    for domain <- domains, do: ~r(^#{String.replace(domain, "*.", "(.*\\.)*")}$)
  end

  @spec subdomain_match?([Regex.t()], String.t()) :: boolean()
  def subdomain_match?(domains, host) do
    Enum.any?(domains, fn domain -> Regex.match?(domain, host) end)
  end
end
