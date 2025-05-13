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
    @storage = app.settings.storage
  end

  def teardown
    # Clear all data from tables
    @storage.query('TRUNCATE users CASCADE;')
    @storage.query('TRUNCATE disciplines CASCADE;')
  end

  # Admin Schedule Page
  def test_admin_schedule_one_appointment
    date = '2025-05-12'
    create_discipline(name: 'Physiotherapy', title: 'PT', clinical: true)
    binding.pry
    create_practitioner
    create_patient
    create_appointment
    # Displays: Date, Disciplines, Practitioners, and Appointments
    # date = ___
    # create appointments (staff: annie, )
    # create practitioners (annie, )
    get '/admin/schedule/'

    assert_equal(200, last_response.status)

  end

  private

  # Helpers for generating test data before tests
  def create_discipline(discipline)
    name     = discipline[:name]
    title    = discipline[:title]
    clinical = discipline[:clinical]

    sql = "INSERT INTO disciplines(name, title, clinical)
           VALUES($1, $2, $3);"
    @storage.query(sql, name, title, clinical)
  end

  def create_user(name, birthday)
    
  end
end