#!/usr/bin/env ruby
require "csv"
require "set"
require_relative "rules"

HERE = __dir__

def load_csv(name)
  CSV.read(File.join(HERE, name), headers: true).map(&:to_h)
end

def load_disbursements
  load_csv("disbursements.csv").each_with_object({}) { |row, h| h[row["hcb_code"]] = row }
end

def load_data_fixes
  load_csv("data_fixes.csv").each_with_object({}) do |row, h|
    code = row["hcb_code"]&.strip
    h[code] = row["tag"].strip if code && !code.empty?
  end
end

transactions = load_csv("raw_transactions.csv")
disbursements = load_disbursements
data_fixes = load_data_fixes

tagged = transactions.map do |txn|
  tag = data_fixes[txn["hcb_code"]] || classify(txn, disbursements)
  txn.merge("tag" => tag)
end

# Summary by tag
tag_summary = Hash.new { |h, k| h[k] = { count: 0, total_cents: 0 } }
tagged.each do |t|
  tag_summary[t["tag"]][:count] += 1
  tag_summary[t["tag"]][:total_cents] += t["amount_cents"].to_i
end

puts "=" * 70
puts "SoM Cost Pipeline — Transaction Summary"
puts "=" * 70
printf "%-20s %7s %12s\n", "Tag", "Count", "Net ($)"
puts "-" * 42
tag_summary.keys.sort.each do |tag|
  s = tag_summary[tag]
  printf "%-20s %7d %12s\n", tag, s[:count], format("%.2f", s[:total_cents] / 100.0).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
end

# Cost calculation
total_cost_cents = tagged.select { |t| COST_TAGS.include?(t["tag"]) }.sum { |t| t["amount_cents"].to_i }

inflow_cents = tagged.select { |t| t["tag"] == "inflow" }.sum { |t| t["amount_cents"].to_i }
passthrough_cents = tagged.select { |t| t["tag"].start_with?("pass-through") }.sum { |t| t["amount_cents"].to_i }
selftransfer_cents = tagged.select { |t| t["tag"] == "self-transfer" }.sum { |t| t["amount_cents"].to_i }
balance_cents = inflow_cents + passthrough_cents + selftransfer_cents + total_cost_cents

fmt = ->(cents) { format("%12s", format("%.2f", cents / 100.0).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse) }

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

# Write tagged output
outpath = File.join(HERE, "tagged_transactions.csv")
CSV.open(outpath, "w") do |csv|
  csv << tagged.first.keys
  tagged.each { |t| csv << t.values }
end
puts "\nTagged transactions written to #{outpath}"

# Write cost-only output
cost_path = File.join(HERE, "cost_transactions.csv")
cost_txns = tagged.select { |t| COST_TAGS.include?(t["tag"]) }
CSV.open(cost_path, "w") do |csv|
  csv << cost_txns.first.keys unless cost_txns.empty?
  cost_txns.each { |t| csv << t.values }
end
puts "Cost-only transactions written to #{cost_path}"
