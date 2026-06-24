require_relative "hcb"
require_relative "rules"

module Pipeline
  def self.run(slug)
    org = HCB.org(slug)
    org_id = org["id"]
    org_balance = org.dig("balances", "balance_cents")

    transactions = HCB.transactions(slug)

    transfers = transactions.select { |t| t["type"] == "transfer" && t["transfer"] }
    transfer_cache = {}
    transfers.each do |t|
      transfer_cache[t["id"]] = HCB.transfer(t["transfer"]["href"])
    end

    tagged = transactions.map do |txn|
      transfer_info = transfer_cache[txn["id"]]
      tag = classify(txn, transfer_info, org_id)
      {
        id: txn["id"],
        amount_cents: txn["amount_cents"],
        memo: txn["memo"],
        date: txn["date"],
        type: txn["type"],
        tag: tag
      }
    end

    txn_total_cents = tagged.sum { |t| t[:amount_cents].to_i }
    total_cost_cents = tagged.select { |t| COST_TAGS.include?(t[:tag]) }.sum { |t| t[:amount_cents].to_i }
    inflow_cents = tagged.select { |t| t[:tag] == "inflow" }.sum { |t| t[:amount_cents].to_i }
    passthrough_cents = tagged.select { |t| t[:tag].start_with?("pass-through") }.sum { |t| t[:amount_cents].to_i }
    selftransfer_cents = tagged.select { |t| t[:tag] == "self-transfer" }.sum { |t| t[:amount_cents].to_i }
    balance_cents = inflow_cents + passthrough_cents + selftransfer_cents + total_cost_cents
    naive_cost_cents = tagged.select { |t| t[:amount_cents].to_i < 0 }.sum { |t| t[:amount_cents].to_i }

    tag_summary = Hash.new { |h, k| h[k] = { count: 0, total_cents: 0 } }
    tagged.each do |t|
      tag_summary[t[:tag]][:count] += 1
      tag_summary[t[:tag]][:total_cents] += t[:amount_cents].to_i
    end

    {
      org: { id: org_id, name: org["name"], slug: slug },
      transaction_count: transactions.length,
      balance_check: {
        transaction_sum_cents: txn_total_cents,
        reported_balance_cents: org_balance,
        match: txn_total_cents == org_balance
      },
      tags: tag_summary.sort.to_h,
      cost_derivation: {
        inflow_cents: inflow_cents,
        balance_cents: balance_cents,
        passthrough_cents: passthrough_cents,
        selftransfer_cents: selftransfer_cents,
        total_cost_cents: total_cost_cents.abs,
        naive_cost_cents: naive_cost_cents.abs,
        overcounting_removed_cents: (total_cost_cents - naive_cost_cents).abs
      },
      transactions: tagged
    }
  end
end
