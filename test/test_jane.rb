ENV['RACK_ENV'] = 'test'

require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/autorun'
require 'rack/test'
require 'pry'

require_relative '../jane'

class TestJane < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    app.settings.storage = PGAdapter.new
  end

  # Admin Schedule Page
  def test_admin_schedule
    # Displays: Date, Disciplines, Practitioners, and Appointments
    # date = ___
    # create appointments (staff: annie, )
    # create practitioners (annie, )
    get '/admin/schedule/'
    assert_equal(200, last_response.status)
  end

  private

  # Helpers for generating test data before tests
  def create_user(name, birthday)
    
  end
end