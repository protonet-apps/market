require 'sinatra'
require 'haml'
require 'sequel'
require 'logger'
require 'json'
require 'amqp'

if ENV.key? 'DATABASE_URL'
  DB = Sequel.connect ENV['DATABASE_URL']
  raise 'Not migrated' unless DB.table_exists?(:repos)
elsif ENV['RACK_ENV'] != 'production'
  DB = Sequel.sqlite
  require './migrate'
else
  raise 'Running production mode without a database'
end
DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] != 'production'

EM.next_tick do
  MQ.queue("create").subscribe do |payload|
    puts "Received a message: #{payload}"
  end
end

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

set :protection, :except => :frame_options

get '/' do
  @repos = {}
  DB[:repos].each do |repo|
    @repos[repo[:id]] = JSON.parse repo[:json]
  end
  
  DB[:apps].each do |app|
    manifest = JSON.parse app[:json]
    next unless repo = @repos[app[:repo_id]]
    next unless entry = repo['apps'].find {|e| e['name'] == manifest['name'] }
    entry['installed'] = manifest
  end
  
  #@apps = @repos.values.map {|r| r['apps'].map {|a| a.merge('repo' => r) } }.flatten
  haml :index, :format => :html5
end

get '/:rid/:app' do |rid, app|
  pass unless @repo = DB[:repos].first(:id => rid)
  @repo_info = JSON.parse @repo[:json]
  pass unless @app = @repo_info['apps'].find {|e| e['name'] == app }
  
  @installs = []
  DB[:apps].where(:repo_id => rid).each do |app|
    manifest = JSON.parse app[:json]
    next unless @app['name'] == manifest['name']
    @installs << manifest
  end
  
  haml :show, :format => :html5
end

get '/one' do |repo_id|
  @repos = DB[:repos].map {|r| r.merge(:data => JSON.parse(r[:json])) }
  @repo = @repos.find {|r| r[:id] == repo_id }

  @apps = @repo[:data]['apps']
  
  DB[:apps].where(:repo_id => repo_id).each do |app|
    manifest = JSON.parse app[:json]
    next unless entry = @apps.find {|e| e['name'] == manifest['name'] }
    entry['installed'] = manifest
  end
  
  haml :repo, :format => :html5
end

