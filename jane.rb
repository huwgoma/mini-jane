# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'
require 'date_core'
require_relative 'pg_adapter'
Dir.glob('lib/*.rb').each { |file| require_file }

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)

  set :erb, :escape_html => true
end

configure :development do
  require 'pry'
  require 'sinatra/reloader'
  also_reload 'pg_adapter.rb', 'lib/*.rb'
end

# Routes
before do
  @storage = PGAdapter.new(logger: logger)
end

not_found do
  redirect '/admin/schedule'
end

# 
get '/admin/schedule' do
  # Schedule Loading
  # - Things we need to load in no particular order:
  #   - Practitioners (all for now, but eventually shift-specific)
  #     - Each practitioner's clinical discipline(s)
  #     - Each practitioner's ID
  #   - 
  @date = Date.today.to_s
  @appointments = @storage.load_daily_appointments(@date)

  erb :schedule 
end