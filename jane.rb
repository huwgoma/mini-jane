# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'
require_relative 'pg_adapter'
Dir.glob('lib/*.rb').each { |file| require_relative file }

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

before do
  @storage = PGAdapter.new
end

get '/' do
  @schedule = @storage.load_daily_schedule(Date.today.to_s)
  # { Physiotherapy: 
  #   { 1 => Practitioner(@id = 1, @name = ...,
  #       @appts = [Appointment(@id=1, @patient='',)])
  #   }
  # }
end