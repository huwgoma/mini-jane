ENV['RACK_ENV'] = 'test'

require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/autorun'
require 'rack/test'
require 'pry'

require_relative '../jane'

class TestJane < Minitest::Test
  include Rack::Test::Methods

  DISCIPLINE_TITLES = { 
    'Physiotherapy' => 'PT', 'Massage Therapy' => 'MT', 'Chiropractic' => 'DC'
  }

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
                               datetime: '2025-05-12 10:00AM', discipline: 'Physiotherapy',
                               tx_name: 'PT - Initial', tx_length: 45, tx_price: 100.00)

    # create_discipline(name: 'Physiotherapy', title: 'PT', clinical: true)    
    

    # insert_discipline(name: 'Physiotherapy', title: 'PT', clinical: true)
    # insert_treatment(name: 'PT - Ax', discipline_id: )
    # binding.pry
    # create_practitioner
    # create_patient
    # create_appointment
    # Displays: Date, Disciplines, Practitioners, and Appointments
    # date = ___
    # create appointments (staff: annie, )
    # create practitioners (annie, )
    get '/admin/schedule/'

    assert_equal(200, last_response.status)

  end

  private

  # Helpers for generating test data before tests
  def create_appointment_cascade(staff_name:, patient_name:, 
                                 datetime:, discipline:,
                                 tx_name:, tx_length:, tx_price:)

    staff_id = insert_user_returning_id(staff_name)
    patient_id = insert_user_returning_id(patient_name)

    insert_user_profile(staff_id, table: 'staff')
    insert_user_profile(patient_id, table: 'patients')

    discipline_id = insert_discipline_returning_id(discipline)
    treatment_id = insert_treatment_returning_id(tx_name, discipline_id, tx_length, tx_price)
    binding.pry

    # Create discipline (based on tx name's prefix) (eg. PT -> Physiotherapy) -> d id
    # Create treatment (discipline id)
    # Insert record into staff_disciplines join
    # 
    # Create appt
  end

  def insert_user_returning_id(full_name)
    first_name, last_name = full_name.split(' ')
    sql = "INSERT INTO users (first_name, last_name)
           VALUES ($1, $2) RETURNING id;"
    result = @storage.query(sql, first_name, last_name)

    result.first['id'].to_i
  end

  def insert_user_profile(user_id, table: 'patients')
    sql = "INSERT INTO #{table} (user_id) VALUES ($1)"
    @storage.query(sql, user_id)
  end

  def insert_discipline_returning_id(discipline, clinical: true)
    title = DISCIPLINE_TITLES[discipline]
    
    sql = "INSERT INTO disciplines(name, title, clinical)
           VALUES($1, $2, $3) RETURNING id;"
    result = @storage.query(sql, discipline, title, clinical)

    result.first['id'].to_i
  end

  def insert_treatment_returning_id(name, discipline_id, length, price)
    sql = "INSERT INTO treatments (name, discipline_id, length, price)
           VALUES($1, $2, $3, $4) RETURNING id;"
    result = @storage.query(sql, name, discipline_id, length, price)

    result.first['id'].to_i
  end
end