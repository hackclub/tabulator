# Universal rules for categorizing YSWS program transactions.
#
# These must work across ALL programs with zero human judgment.
# Anything requiring a human to read a memo and decide belongs in data_fixes.csv.
#
# Tags:
#   "inflow"        - money coming into the program (excluded from cost)
#   "self-transfer" - internal card grant plumbing (excluded, nets to zero)
#   "pass-through"  - money leaving but not a program cost (excluded)
#   "cost"          - real program spending (counted in cost/hr)

ORGANIZER_BUDGET_IDS = begin
  path = File.join(__dir__, "organizer_budgets.txt")
  if File.exist?(path)
    File.readlines(path).filter_map { |line| line.split[0] if line.strip.length > 0 }.to_set
  else
    Set.new
  end
end

COST_TAGS = Set["cost"].freeze
EXCLUDED_TAGS = Set["inflow", "pass-through", "self-transfer"].freeze

def classify(txn, disbursements)
  hcb = txn["hcb_code"]
  amount = txn["amount_cents"].to_i

  disb = disbursements[hcb]

  if disb
    src_id = disb["source_event_id"]
    dst_id = disb["dest_event_id"]

    return "inflow" if amount > 0 && src_id != dst_id
    return "self-transfer" if src_id == dst_id
    return "pass-through" if ORGANIZER_BUDGET_IDS.include?(dst_id)
    return "cost" if amount < 0
  end

  return "inflow" if amount > 0

  "cost"
end
