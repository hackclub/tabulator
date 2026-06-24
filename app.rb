require "sinatra"
require "json"
require_relative "pipeline"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 4567)
set :host_authorization, permitted: ENV.fetch("PERMITTED_HOSTS", "").split(",").push("localhost")

get "/" do
  content_type :json
  { status: "ok", usage: "GET /organizations/:slug" }.to_json
end

get "/organizations/:slug" do
  content_type :json
  Pipeline.new(params[:slug]).to_h.to_json
rescue => e
  status 500
  { error: e.message }.to_json
end
