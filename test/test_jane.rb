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

  def test_admin_schedule_fixed_date_one_practitioner_one_appointment
    date = '2024-10-08'

    staff_id = return_id(create_user('Annie Hu'))
    create_profile(staff_id, type: 'staff')

    patient_id = return_id(create_user('Hugo Ma'))
    create_profile(patient_id)

    discipline_id = return_id(create_discipline('Physiotherapy', title: 'PT'))
    treatment_id = return_id(create_treatment('PT - Initial', discipline_id, 
                                              length: 45, price: 100.00))
    binding.pry
    # create_appointment_cascade(staff_name: 'Annie Hu', patient_name: 'Hugo Ma',
    #                            datetime: "#{date} 10:00AM", discipline: 'Physiotherapy',
    #                            tx_name: 'PT - Initial', tx_length: 45, tx_price: 100.00)

    get '/admin/schedule/2024-10-08'

    assert_includes(last_response.body, "<h2>#{date}")
    assert_includes(last_response.body, 'Physiotherapy')
    assert_includes(last_response.body, 'Annie Hu')
    assert_includes(last_response.body, "#{date} 10:00:00 - Hugo Ma - PT - Initial")
  end

  def test_admin_schedule_default_today
    skip
    today = Date.today.to_s
    yesterday = Date.today.prev_day.to_s

    # Appointment scheduled for today; should be displayed.
    # - Capture PG::Result object for use in subsequent appointments
    appointment = create_appointment_cascade(
                  staff_name: 'Annie Hu', patient_name: 'Hugo Ma', 
                  datetime: "#{today} 10:00AM", discipline: 'Physiotherapy',
                  tx_name: 'PT - Treatment', tx_length: 30, tx_price: 85.00
                 ).first


    # Appointment scheduled for yesterday - Should not be displayed
    # staff_name: 'Annie Hu', patient_name: 'Hugo Ma',
    # datetime: "#{yesterday} 10:00AM", discipline: 'Physiotherapy',
    # tx_name: 'PT - Initial', tx_length: 45, tx_price: 100.00)

    get '/admin/schedule/'

    assert_includes(last_response.body, 'PT - Treatment')
    refute_includes(last_response.body, 'PT - Initial')
  end


  private
  
  
  #################################################
  # Helpers for generating test data before tests #
  #################################################
  # Return the ID from a PG::Result object
  def return_id(result)
    result.first['id'].to_i  
  end

  # Create a dummy user
  def create_user(name)
    first_name, last_name = name.split
    
    sql = "INSERT INTO users(first_name, last_name) VALUES($1, $2) RETURNING *;"
    @storage.query(sql, first_name, last_name)
  end

  # Create a dummy profile (staff/patient)
  def create_profile(user_id, type: 'patients')
    sql = "INSERT INTO #{type} (user_id) VALUES ($1) RETURNING *;"
    @storage.query(sql, user_id)
  end

  # Create a dummy discipline
  def create_discipline(name, title: '', clinical: true)
    sql = "INSERT INTO disciplines (name, title, clinical)
           VALUES($1, $2, $3) RETURNING *;"
    @storage.query(sql, name, title, clinical)
  end

  # Create a dummy treatment type
  def create_treatment(name, discipline_id, length:, price:)
    
  end




  def create_appointment_cascade(staff_name:, patient_name:, datetime:, 
                                 discipline:, tx_name:, tx_length:, tx_price:)
    staff_id = insert_user_returning_id(staff_name)
    patient_id = insert_user_returning_id(patient_name)
    insert_user_profile(staff_id, table: 'staff')
    insert_user_profile(patient_id, table: 'patients')

    discipline_id = insert_discipline_returning_id(discipline)
    treatment_id = insert_treatment_returning_id(tx_name, discipline_id, tx_length, tx_price)
    insert_staff_discipline(staff_id, discipline_id)
    
    insert_and_return_appointment(staff_id, patient_id, datetime, treatment_id)
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

  def insert_staff_discipline(staff_id, discipline_id)
    sql = "INSERT INTO staff_disciplines(staff_id, discipline_id)
           VALUES ($1, $2);"
    @storage.query(sql, staff_id, discipline_id)
  end

  def insert_and_return_appointment(staff_id, patient_id, datetime, treatment_id)
    sql = "INSERT INTO appointments (staff_id, patient_id, datetime, treatment_id)
           VALUES($1, $2, $3, $4) RETURNING *;"
    @storage.query(sql, staff_id, patient_id, datetime, treatment_id)
  end
end