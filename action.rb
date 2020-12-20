# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "date"
require "nokogiri"
require "open-uri"

LOGINNAME = ENV["loginname"]
PASSWORD = ENV["password"]

def request_options(uri)
  { use_ssl: uri.scheme == "https" }
end

def fetch_jwt_token
  uri = URI.parse("https://bootcamp.fjord.jp/api/session")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request.body = JSON.dump({
                             "login_name" => LOGINNAME,
                             "password" => PASSWORD
                           })
  response = http_request(uri, request)
  response.body.gsub(/{\"token\":\"|"}/, "")
end

def http_request(uri, request)
  Net::HTTP.start(uri.hostname, uri.port, request_options(uri)) do |http|
    http.request(request)
  end
end

def fetch_csrf_token
  uri = URI.parse("https://bootcamp.fjord.jp/")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = fetch_jwt_token
  response = http_request(uri, request)
  re = Regexp.new("csrf-token.+?==")
  s = response.body
  csrf_token = re.match(s).to_s.gsub('csrf-token" content="', "")
  { csrf_token: csrf_token, cookie: extract_cookie(response) }
end

def extract_cookie(response)
  cookie = {}
  response.get_fields("Set-Cookie").each do |str|
    k, v = str[0...str.index(";")].split("=")
    cookie[k] = v
  end
  cookie
end

def add_cookie(request, cookie)
  request.add_field("Cookie", cookie.map do |k, v|
    "#{k}=#{v}"
  end.join(";"))
  request
end

def create_item(item_node)
  title_anchor = item_node.css(".thread-list-item__title-link")[0]
  username_anchor = item_node.css(".thread-list-item-meta .thread-header__author")[0]
  report_datetime_anchor = item_node.css(".thread-list-item-meta__datetime")[0]
  user_icon_anchor = item_node.css(".thread-list-item__author-icon")[0]

  is_wip = item_node.css(".is-wip").length > 0

  title = is_wip ? "【WIP】#{title_anchor.inner_text}" : title_anchor.inner_text
  report_url = "https://bootcamp.fjord.jp#{title_anchor.attributes["href"].value}"
  username = username_anchor.inner_text
  report_datetime = report_datetime_anchor.inner_text
  subtitle = "#{username} #{report_datetime}"
  icon_path = "./#{username}.png"
  user_icon_url = user_icon_anchor.attributes["src"]

  if !File.exist?(icon_path)
    save_icon(user_icon_url, icon_path)
  end

  {
    title: title,
    subtitle: subtitle,
    arg: report_url,
    wip: is_wip,
    icon: {
       path: icon_path
    }
  }
end

def save_icon(url, icon_path)
  open(icon_path, "w+b") do |output|
    open(url) do |data|
      output.puts(data.read)
    end
  end
end

def get_reports(token)
  uri = URI.parse("https://bootcamp.fjord.jp/reports")
  request = Net::HTTP::Get.new(uri)
  request.content_type = "text/html"
  request = add_cookie(request, token[:cookie])
  response = http_request(uri, request)
  doc = Nokogiri::HTML.parse(response.body, nil, "utf-8")
  thread_list_items =  doc.css(".thread-list-item")
  items = Proc.new {
    items = thread_list_items.map(&method(:create_item))
    items = filter_wip(items) if wip_filterable?
    items
  }.call

  {
    items: items
  }.to_json
end

def wip_filterable?
  ARGV[0] == "nowip"
end

def filter_wip(reports)
  reports.select { |report| report[:wip] == false }
end

token = fetch_csrf_token

if (PASSWORD == "password") && (LOGINNAME == "username")
  puts "LOGINNAMEとPASSWORDを設定してください"
  return
end

puts get_reports(token)
