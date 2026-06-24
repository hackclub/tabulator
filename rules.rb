require "set"

module Rules
  ORGANIZER_BUDGET_IDS = begin
    path = File.join(__dir__, "organizer_budgets.txt")
    if File.exist?(path)
      File.readlines(path).filter_map { |line| line.split[0] if line.strip.length > 0 }.to_set
    else
      Set.new
    end
  end

  def self.classify(txn)
    return classify_transfer(txn) if txn.transfer?
    return "inflow" if txn.amount_cents > 0
    "cost"
  end

  def self.classify_transfer(txn)
    return "inflow" if txn.amount_cents > 0 && txn.source_org_id != txn.org_id
    return "self-transfer" if txn.source_org_id == txn.dest_org_id
    return "pass-through" if ORGANIZER_BUDGET_IDS.include?(txn.dest_org_id)
    return "cost" if txn.amount_cents < 0
    "inflow"
  end
end
