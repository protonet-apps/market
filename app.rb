require 'sinatra'
require 'haml'
require 'sequel'
require 'logger'
require 'json'
require './rpc'

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
    icon ? (root + icon) : '/noicon.png'
  end
end

set :protection, :except => :frame_options

before { request.script_name = request['X-SCRIPT-NAME'] }

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
  pass unless @repo = DB[:repos].first(:id => rid)
  @repo_info = JSON.parse @repo[:json]
  pass unless @app = @repo_info['apps'].find {|e| e['name'] == app }
  @app['repo_id'] = @repo[:id]
  @app['repo'] = @repo_info
  
  stream(:keep_open) do |out|
    out << 
  '<!DOCTYPE html><html><head><link href="http://fonts.googleapis.com/css?family=Eagle+Lake" rel="stylesheet" type="text/css"><script src="https://ajax.googleapis.com/ajax/libs/jquery/1.8.1/jquery.min.js"></script></head><body><div style="font-family: \'Eagle Lake\';width:500px;font-size:2em;margin: 10% auto 5% auto;"><img src="/loading.png" style="-moz-transform-origin:25.5px 25.5px;"><script>var i=0;setInterval(function(){i=(i+30)%360;$("img").css({"-moz-transform":"rotate("+i+"deg)"});},50);</script><h1 style="display:inline;margin-left:25px;">Installing...</h1></div><pre>Status:<br/>'
    Rpc.fire 'install', :uri => @app['repository']['url'] do |err, result|
      out << result << '<br/>'
      
      next if err == 'partial'
      sleep 5
      out << '</pre><script>document.location="http://wiki.protonet.danopia.net:7200/";</script></body></html>'
      out.close
    end
  end
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

