#!/usr/bin/env ruby
require "net/http"
require "json"
require "set"
require_relative "rules"

HCB_API = "https://hcb.hackclub.com/api/v3"
HCB_HOST = "hcb.hackclub.com"

$http = Net::HTTP.new(HCB_HOST, 443)
$http.use_ssl = true
$http.open_timeout = 30
$http.read_timeout = 30
$http.start

def hcb_get(path)
  res = $http.get("/api/v3#{path}")
  raise "HCB API error #{res.code}: #{path}" unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
end

def fetch_all_transactions(slug)
  txns = []
  page = 1
  loop do
    batch = hcb_get("/organizations/#{slug}/transactions?per_page=100&page=#{page}")
    break if batch.empty?
    txns.concat(batch)
    page += 1
  end
  txns
end

def fetch_transfer_info(transfer_href)
  path = transfer_href.sub("https://hcb.hackclub.com/api/v3", "")
  data = hcb_get(path)
  {
    source_org_id: data.dig("source_organization", "id"),
    dest_org_id: data.dig("organization", "id")
  }
end

slug = ARGV[0]
unless slug
  $stderr.puts "Usage: ruby run_pipeline.rb <org-slug>"
  exit 1
end

$stderr.puts "Fetching org info..."
org = hcb_get("/organizations/#{slug}")
org_id = org["id"]
org_balance = org.dig("balances", "balance_cents")
$stderr.puts "  #{org["name"]} (#{org_id})"

$stderr.puts "Fetching transactions..."
transactions = fetch_all_transactions(slug)
$stderr.puts "  #{transactions.length} transactions"

transfers = transactions.select { |t| t["type"] == "transfer" && t["transfer"] }
$stderr.puts "Fetching #{transfers.length} transfer details..."

transfer_cache = {}
transfers.each_with_index do |t, i|
  href = t["transfer"]["href"]
  transfer_cache[t["id"]] = fetch_transfer_info(href)
  $stderr.print "\r  #{i + 1}/#{transfers.length}" if (i + 1) % 10 == 0 || i + 1 == transfers.length
end
$stderr.puts

tagged = transactions.map do |txn|
  transfer_info = transfer_cache[txn["id"]]
  tag = classify(txn, transfer_info, org_id)
  { **txn, "tag" => tag }
end

# Balance check
txn_total_cents = tagged.sum { |t| t["amount_cents"].to_i }
if txn_total_cents != org_balance
  $stderr.puts "WARNING: transaction sum (#{txn_total_cents}) != org balance (#{org_balance})"
else
  $stderr.puts "Balance check passed (#{org_balance})"
end

# Summary by tag
tag_summary = Hash.new { |h, k| h[k] = { count: 0, total_cents: 0 } }
tagged.each do |t|
  tag_summary[t["tag"]][:count] += 1
  tag_summary[t["tag"]][:total_cents] += t["amount_cents"].to_i
end

fmt = ->(cents) { format("%12s", format("%.2f", cents / 100.0).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse) }

puts "=" * 70
puts "#{org["name"]} — Transaction Summary"
puts "=" * 70
printf "%-20s %7s %12s\n", "Tag", "Count", "Net ($)"
puts "-" * 42
tag_summary.keys.sort.each do |tag|
  s = tag_summary[tag]
  printf "%-20s %7d %s\n", tag, s[:count], fmt.(s[:total_cents])
end

total_cost_cents = tagged.select { |t| COST_TAGS.include?(t["tag"]) }.sum { |t| t["amount_cents"].to_i }
inflow_cents = tagged.select { |t| t["tag"] == "inflow" }.sum { |t| t["amount_cents"].to_i }
passthrough_cents = tagged.select { |t| t["tag"].start_with?("pass-through") }.sum { |t| t["amount_cents"].to_i }
selftransfer_cents = tagged.select { |t| t["tag"] == "self-transfer" }.sum { |t| t["amount_cents"].to_i }
balance_cents = inflow_cents + passthrough_cents + selftransfer_cents + total_cost_cents

puts
puts "=" * 70
puts "Cost Derivation"
puts "=" * 70
puts "  Total inflows       $#{fmt.(inflow_cents)}"
puts "  - Current balance   $#{fmt.(balance_cents)}"
puts "  - Pass-throughs     $#{fmt.(-passthrough_cents)}"
puts "  - Self-transfers    $#{fmt.(-selftransfer_cents)}"
puts "                      #{"─" * 12}"
puts "  = Total cost        $#{fmt.(-total_cost_cents)}"

naive_cost = tagged.select { |t| t["amount_cents"].to_i < 0 }.sum { |t| t["amount_cents"].to_i }
puts
puts "  Naive total outflow:  $#{fmt.(-naive_cost)}"
puts "  Overcounting removed: $#{fmt.((total_cost_cents - naive_cost))}"
