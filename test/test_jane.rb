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

    create_appointment_cascade(staff_name: 'Annie Hu', patient_name: 'Hugo Ma',
                               datetime: '2025-05-12 10:00AM',
                               tx_name: 'PT - Initial', tx_length: 45)

    create_discipline(name: 'Physiotherapy', title: 'PT', clinical: true)    
    

    insert_discipline(name: 'Physiotherapy', title: 'PT', clinical: true)
    insert_treatment(name: 'PT - Ax', discipline_id: )
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
  def create_appointment_cascade(staff_name:, patient_name:, datetime:,
                                 tx_name:, tx_length:)
    user_id = insert_user_returning_id(staff_name)
    binding.pry
    # Create user (staff and patient) -> user ids (staff and patient)
    # Create staff profile (user id (staff)) and patient profile (user id (patient))
    # 
    # Create discipline (based on tx name's prefix) (eg. PT -> Physiotherapy) -> d id
    # Create treatment (discipline id)
  end

  def insert_user_returning_id(full_name)
    first_name, last_name = full_name.split(' ')
    sql = "INSERT INTO users (first_name, last_name)
           VALUES ($1, $2)
           RETURNING id;"
    result = @storage.query(sql, first_name, last_name)

    result.first['id'].to_i
  end
  

  #
  def insert_and_return_discipline(discipline)
    name     = discipline[:name]
    title    = discipline[:title]
    clinical = discipline[:clinical]

    sql = "INSERT INTO disciplines(name, title, clinical)
           VALUES($1, $2, $3);"
    @storage.query(sql, name, title, clinical)
  end
end