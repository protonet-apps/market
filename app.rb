require 'sinatra'
require 'haml'
require 'sequel'
require 'logger'
require 'json'

require './rpc'

# Database cookiecutter block
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

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
  
  def icon_url item, size='thumb'
    root = item['iconroot'] || (item['repo'] && item['repo']['iconroot'])
    root ||= item['homepage'] || (item['repo'] && item['repo']['homepage'])
    
    icon = (item['icons'] && item['icons'][size]) || item['icon']
    url(icon ? (root + icon) : '/noicon.png')
  end
end

set :protection, :except => :frame_options

before do
  @user    = JSON.parse(request.env['HTTP_X_USER'   ]) rescue nil
  @context = JSON.parse(request.env['HTTP_X_CONTEXT']) rescue nil
  
  if !@user
    @message = 'You are not logged in to Protonet. You must log in as an administrator before managing apps.'
  elsif !@user['admin']
    @message = 'You are not an administrator on this Protonet node. Only administrators can manage apps.'
  end
end

post '*' do
  pass unless params[:__method]
  call env.merge('REQUEST_METHOD' => params[:__method])
end

get '/' do
  @repos = {}
  DB[:repos].each do |repo|
    data = JSON.parse repo[:json]
    data['apps'].each do |a|
      a['repo_id'] = repo[:id]
      a['repo'] = data
    end
    
    @repos[repo[:id]] = data
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
  @app['repo_id'] = @repo[:id]
  @app['repo'] = @repo_info
  
  @installs = []
  DB[:apps].where(:repo_id => rid).each do |app|
    manifest = JSON.parse app[:json]
    next unless @app['name'] == manifest['name']
    @installs << manifest
  end
  
  haml :show, :format => :html5
end

post '/:rid/:app' do |rid, app|
  pass unless @user && @user['admin'] # TODO: error
  
  pass unless @repo = DB[:repos].first(:id => rid)
  @repo_info = JSON.parse @repo[:json]
  pass unless @app = @repo_info['apps'].find {|e| e['name'] == app }
  @app['repo_id'] = @repo[:id]
  @app['repo'] = @repo_info
  
  Rpc.fire 'install', :uri => @app['repository']['url'] do |err, result|
    next if err == 'partial'
    puts 'app installed'
  end
  
  redirect url('/')
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

