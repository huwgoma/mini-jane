# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'
require 'date_core'
require_relative 'pg_adapter'
Dir.glob('lib/*.rb').each { |file| require_relative file }

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)

  set :erb, :escape_html => true

  set :storage, PGAdapter.new
end

configure :development do
  require 'pry'
  require 'sinatra/reloader'
  also_reload 'pg_adapter.rb', 'lib/*.rb'
end


# Routes
before do
  @storage = settings.storage
end

not_found do
  redirect '/admin/schedule/'
end

######### 
# To Do #
#########
# - Flesh out schedule 
# - CRUD for practitioners
# - CRUD for patients
# - CRUD for appointments
# - CRUD for disciplines
# - CRUD for treatments

# # # # # # # # # # # # 
# Admin Schedule Page # 
# # # # # # # # # # # # 

# Redirect Date (Pretty Date URL)
get '/admin/schedule/redirect' do
  redirect "/admin/schedule/#{params[:date]}"
end

# Main Admin Schedule Page
get '/admin/schedule/:date?' do
  @date = Date.parse(params[:date] || Date.today.to_s)
  @yesterday, @tomorrow = @date.prev_day, @date.next_day
  @schedule = @storage.load_daily_schedule(@date)

  erb :schedule
end