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

  def self.org(slug)
    get("/organizations/#{slug}")
  end

  def self.transactions(slug)
    txns = []
    page = 1
    loop do
      batch = get("/organizations/#{slug}/transactions?per_page=100&page=#{page}")
      break if batch.empty?
      txns.concat(batch)
      page += 1
    end
    txns
  end

  def self.transfer(href)
    path = href.sub("https://hcb.hackclub.com/api/v3", "")
    data = get(path)
    {
      source_org_id: data.dig("source_organization", "id"),
      dest_org_id: data.dig("organization", "id")
    }
  end
end
