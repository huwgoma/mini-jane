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
  @date = Date.today.to_s
  @appointments = @storage.load_daily_appointments(@date)

  binding.pry
  erb :schedule
  # Load:
  # - Date
  # - All practitioners (order by discipline type)
  # - Each practitioner's appointments list (time, treatment name, patient name)
  # - For that day only
end