ENV['RACK_ENV'] = 'test'

require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/autorun'
require 'rack/test'

require_relative '../jane'

class TestJane < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end
end