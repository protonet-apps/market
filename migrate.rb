unless Object.const_defined? 'DB'
  raise 'Not given a database to migrate' unless ENV.key? 'DATABASE_URL'
  
  require 'sequel'
  require 'logger'

  DB = Sequel.connect ENV['DATABASE_URL']
  DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] != 'production'
end

unless DB.table_exists? :repos
  DB.create_table :repos do
    primary_key :id

    Fixnum :user_id, :null => false
    String :json, :null => false, :text => true

    DateTime :created_at, :null => false
    index :created_at
    DateTime :updated_at
  end
  
  DB.create_table :apps do
    primary_key :id
    foreign_key :repo_id, :repos, :null => false
    index       :repo_id

    Fixnum :user_id, :null => false
    String :json, :null => false, :text => true
    String :name, :null => false

    DateTime :created_at, :null => false
    index :created_at
    DateTime :updated_at
  end

  # Some test data
  if ENV['RACK_ENV'] != 'production'
    require 'open-uri'
    require 'json'
    data = open('http://protonet-apps.github.com/apps.json').read
    DB[:repos] << {:user_id => 0, :json => data, :created_at => Time.now}
    
    data = open('./manifest.json').read
    DB[:apps] << {:repo_id => 1, :user_id => 0, :json => data, :name => 'store', :created_at => Time.now}
  end
end

