require_relative "hcb"
require_relative "rules"

class Pipeline
  attr_reader :org, :transactions

  def initialize(slug)
    @org = HCB::Org.new(slug)
    @transactions = org.transactions
  end

  def costs = transactions.select(&:cost?)
  def inflows = transactions.select(&:inflow?)
  def excluded = transactions.select(&:excluded?)

  def by_tag
    transactions.group_by(&:tag).transform_values do |txns|
      { count: txns.length, total_cents: txns.sum(&:amount_cents) }
    end.sort.to_h
  end

  def cost_derivation
    inflow_cents = inflows.sum(&:amount_cents)
    cost_cents = costs.sum(&:amount_cents)
    passthrough_cents = transactions.select { |t| t.tag.start_with?("pass-through") }.sum(&:amount_cents)
    selftransfer_cents = transactions.select { |t| t.tag == "self-transfer" }.sum(&:amount_cents)
    balance_cents = inflow_cents + passthrough_cents + selftransfer_cents + cost_cents
    naive_cents = transactions.select { |t| t.amount_cents < 0 }.sum(&:amount_cents)

    {
      inflow_cents:,
      balance_cents:,
      passthrough_cents:,
      selftransfer_cents:,
      total_cost_cents: cost_cents.abs,
      naive_cost_cents: naive_cents.abs,
      overcounting_removed_cents: (cost_cents - naive_cents).abs
    }
  end

  def balance_check
    txn_sum = transactions.sum(&:amount_cents)
    {
      transaction_sum_cents: txn_sum,
      reported_balance_cents: org.balance_cents,
      match: txn_sum == org.balance_cents
    }
  end

  def to_h
    {
      org: { id: org.id, name: org.name, slug: org.slug },
      transaction_count: transactions.length,
      balance_check:,
      tags: by_tag,
      cost_derivation:,
      transactions: transactions.map(&:to_h)
    }
  end
end
