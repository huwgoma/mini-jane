# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'


configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)

  set :erb, :escape_html => true
end

configure :development do
  require 'sinatra/reloader'
  # also_reload
end

get '/' do
  'Hello'
end