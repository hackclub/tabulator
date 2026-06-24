#!/usr/bin/env ruby
require_relative "pipeline"

slug = ARGV[0]
unless slug
  $stderr.puts "Usage: ruby run_pipeline.rb <org-slug>"
  exit 1
end

$stderr.puts "Running pipeline for #{slug}..."
pipeline = Pipeline.new(slug)

$stderr.puts "  #{pipeline.org.name} (#{pipeline.org.id})"
$stderr.puts "  #{pipeline.transactions.length} transactions"

check = pipeline.balance_check
if check[:match]
  $stderr.puts "Balance check passed (#{check[:reported_balance_cents]})"
else
  $stderr.puts "WARNING: transaction sum (#{check[:transaction_sum_cents]}) != org balance (#{check[:reported_balance_cents]})"
end

fmt = ->(cents) { format("%12s", format("%.2f", cents / 100.0).reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse) }

puts "=" * 70
puts "#{pipeline.org.name} — Transaction Summary"
puts "=" * 70
printf "%-20s %7s %12s\n", "Tag", "Count", "Net ($)"
puts "-" * 42
pipeline.by_tag.each do |tag, s|
  printf "%-20s %7d %s\n", tag, s[:count], fmt.(s[:total_cents])
end

d = pipeline.cost_derivation
puts
puts "=" * 70
puts "Cost Derivation"
puts "=" * 70
puts "  Total inflows       $#{fmt.(d[:inflow_cents])}"
puts "  - Current balance   $#{fmt.(d[:balance_cents])}"
puts "  - Pass-throughs     $#{fmt.(-d[:passthrough_cents])}"
puts "  - Self-transfers    $#{fmt.(-d[:selftransfer_cents])}"
puts "                      #{"─" * 12}"
puts "  = Total cost        $#{fmt.(d[:total_cost_cents])}"
puts
puts "  Naive total outflow:  $#{fmt.(d[:naive_cost_cents])}"
puts "  Overcounting removed: $#{fmt.(d[:overcounting_removed_cents])}"
