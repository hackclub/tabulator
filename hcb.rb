require "net/http"
require "json"

module HCB
  API_HOST = "hcb.hackclub.com"

  def self.connection
    @http ||= begin
      http = Net::HTTP.new(API_HOST, 443)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = 30
      http.start
      http
    end
  end

  def self.get(path)
    res = connection.get("/api/v3#{path}")
    raise "HCB API error #{res.code}: #{path}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  def self.get_or_nil(path)
    res = connection.get("/api/v3#{path}")
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  class Org
    attr_reader :id, :name, :slug, :balance_cents

    def initialize(slug)
      data = HCB.get("/organizations/#{slug}")
      @id = data["id"]
      @name = data["name"]
      @slug = slug
      @balance_cents = data.dig("balances", "balance_cents")
    end

    def transactions
      @transactions ||= fetch_all_transactions.map { |data| Transaction.new(data, self) }
    end

    private

    def fetch_all_transactions
      Enumerator.new do |y|
        page = 1
        loop do
          batch = HCB.get("/organizations/#{slug}/transactions?per_page=100&page=#{page}")
          break if batch.empty?
          batch.each { |t| y << t }
          page += 1
        end
      end.to_a
    end
  end

  class Transfer
    attr_reader :source_org_id, :dest_org_id

    def self.fetch(href)
      path = href.sub("https://hcb.hackclub.com/api/v3", "")
      data = HCB.get_or_nil(path)
      data ? new(data) : nil
    end

    def initialize(data)
      @source_org_id = data.dig("source_organization", "id")
      @dest_org_id = data.dig("organization", "id")
    end
  end

  class Transaction
    attr_reader :id, :amount_cents, :memo, :date, :type, :tag

    def initialize(data, org)
      @id = data["id"]
      @amount_cents = data["amount_cents"]
      @memo = data["memo"]
      @date = data["date"]
      @type = data["type"]
      @org = org
      @transfer = Transfer.fetch(data["transfer"]["href"]) if data["type"] == "transfer" && data["transfer"]
      @tag = Rules.classify(self)
    end

    def transfer? = !!@transfer
    def cost? = @tag == "cost"
    def inflow? = @tag == "inflow"
    def excluded? = !cost?

    def source_org_id = @transfer&.source_org_id
    def dest_org_id = @transfer&.dest_org_id
    def org_id = @org.id

    def to_h
      { id:, amount_cents:, memo:, date:, type:, tag: }
    end
  end
end
