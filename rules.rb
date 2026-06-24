# Universal rules for categorizing YSWS program transactions.
#
# These must work across ALL programs with zero human judgment.
#
# Tags:
#   "inflow"        - money coming into the program (excluded from cost)
#   "self-transfer" - internal card grant plumbing (excluded, nets to zero)
#   "pass-through"  - money leaving but not a program cost (excluded)
#   "cost"          - real program spending (counted in cost/hr)

require "set"

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

# txn: hash from HCB API transaction endpoint
# transfer_info: nil, or {source_org_id:, dest_org_id:} from the transfer endpoint
# org_id: the org we're analyzing (to detect self-transfers vs inflows)
def classify(txn, transfer_info, org_id)
  amount = txn["amount_cents"].to_i

  if transfer_info
    src = transfer_info[:source_org_id]
    dst = transfer_info[:dest_org_id]

    return "inflow" if amount > 0 && src != org_id
    return "self-transfer" if src == dst
    return "pass-through" if ORGANIZER_BUDGET_IDS.include?(dst)
    return "cost" if amount < 0
  end

  return "inflow" if amount > 0

  "cost"
end
