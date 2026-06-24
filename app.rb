require "sinatra"
require "json"
require_relative "pipeline"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 4567)

get "/" do
  content_type :json
  { status: "ok", usage: "GET /organizations/:slug" }.to_json
end

get "/organizations/:slug" do
  content_type :json
  result = Pipeline.run(params[:slug])
  result.to_json
rescue => e
  status 500
  { error: e.message }.to_json
end
