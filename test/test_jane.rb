ENV['RACK_ENV'] = 'test'

require 'minitest/reporters'
Minitest::Reporters.use!
require 'minitest/autorun'
require 'rack/test'
require 'pry'
require 'nokogiri'

require_relative '../jane'

class TestJane < Minitest::Test
  include Rack::Test::Methods

  TODAY = Date.today.to_s

  def app
    Sinatra::Application
  end

  def setup
    app.settings.storage = PGAdapter.new
    @storage = app.settings.storage
  end

  def teardown
    # Clear all data from tables
    @storage.query("SELECT set_config('client_min_messages', 'warning', 'false');")
    @storage.query("TRUNCATE users RESTART IDENTITY CASCADE;")
    @storage.query("TRUNCATE disciplines RESTART IDENTITY CASCADE;")
  end
  
  #######################
  # Admin Schedule Page #
  ####################### 
  def test_empty_admin_schedule_default_today
    get '/admin/schedule/'

    assert_includes(last_response.body, TODAY)
    assert_includes(last_response.body, "you don't have any practitioners scheduled for today.")
  end

  def test_admin_schedule_display_appointments_for_selected_date_only
    yesterday = Date.today.prev_day.to_s

    # Appointment scheduled for today; should be displayed.
    context = create_appointment_cascade(
      staff: { name: 'Annie Hu', create_profile: true },
      patient: { name: 'Hugo Ma', create_profile: true },
      discipline: { name: 'Physiotherapy', title: 'PT' },
      treatment: { name: 'PT - Treatment', length: 30, price: 85.00 },
      datetime: "#{TODAY} 10:00AM"
    )
    
    # Appointment scheduled for yesterday; should not be displayed.
    create_appointment_cascade(
      staff: { id: context[:staff_id] },
      patient: { id: context[:patient_id] },
      discipline: { id: context[:discipline_id] },
      treatment: { name: 'PT - Initial', length: 45, price: 100.00 },
      datetime: "#{yesterday} 10:00AM"
    )

    get '/admin/schedule/'

    assert_includes(last_response.body, 'PT - Treatment')
    refute_includes(last_response.body, 'PT - Initial')
  end

  def test_admin_schedule_nested_structure
    date = '2024-10-08'
    time = '10:00AM'

    create_appointment_cascade(
      staff: { name: 'Annie Hu', create_profile: true },
      patient: { name: 'Hugo Ma', create_profile: true },
      discipline: { name: 'Physiotherapy', title: 'PT' },
      treatment: { name: 'PT - Initial', length: 45, price: 100.00 },
      datetime: "#{date} #{time}"
    )

    get '/admin/schedule/2024-10-08'
    doc = Nokogiri::HTML(last_response.body)

    assert_includes(doc.css('h2').map(&:text), date)

    physio_li = doc.css('ul > li').find { |li| li.text.include?('Physiotherapy') }
    refute_nil(physio_li, 'Expected to find an <li> discipline item named Physiotherapy.')

    annie_li = physio_li.css('ul > li').find { |li| li.text.include?('Annie')}
    refute_nil(annie_li, 'Expected to find an <li> practitioner item named Annie.')
    
    appt_li = annie_li.css('ul > li').find { |li| li.text.include?("#{time} - Hugo Ma - PT - Initial") }
    refute_nil(appt_li, 
      "Expected to find an <li> appointment item for #{time} - Hugo Ma - PT - Initial.")
  end

  def test_admin_schedule_multiple_practitioners_one_discipline
    # Annie - Hugo - PT Initial, 10:00AM
    context = create_appointment_cascade(
      staff: { name: 'Annie Hu', create_profile: true },
      patient: { name: 'Hugo Ma', create_profile: true },
      discipline: { name: 'Physiotherapy', title: 'PT' },
      treatment: { name: 'PT - Treatment', length: 30, price: 85.00 },
      datetime: "#{TODAY} 10:00AM"
    )

    # Kevin - Hendrik - PT Treatment, 2:00PM
    create_appointment_cascade(
      staff: { name: 'Kevin Ho', create_profile: true },
      patient: { name: 'Hendrik Swart', create_profile: true },
      discipline: { id: context[:discipline_id] },
      treatment: { id: context[:treatment_id] },
      datetime: "#{TODAY} 2:00PM"
    )

    get '/admin/schedule/'
    doc = Nokogiri::HTML(last_response.body)

    # Assert that the Physiotherapy Discipline has 2 practitioner <li>s.
    physio_list = doc.css('ul>li').find { |li| li.text.include?('Physiotherapy') }.at_css('ul')
    physios = physio_list.css('>li').map(&:text)

    assert_equal(2, physios.size)
    ['Annie Hu', 'Kevin Ho'].each { |name| assert_includes(physios.join, name)}
  end

  def test_admin_schedule_multiple_disciplines
    # Annie - Hugo - PT Initial, 10:00AM
    create_appointment_cascade(
      staff: { name: 'Annie Hu', create_profile: true },
      patient: { name: 'Hugo Ma', create_profile: true },
      discipline: { name: 'Physiotherapy', title: 'PT' },
      treatment: { name: 'PT - Treatment', length: 30, price: 85.00 },
      datetime: "#{TODAY} 10:00AM"
    )
    # Alexis - Hendrik - DC Initial, 12:00PM
    create_appointment_cascade(
      staff: { name: 'Alexis Butler', create_profile: true },
      patient: { name: 'Hendrik Swart', create_profile: true },
      discipline: { name: 'Chiropractic', title: 'DC' },
      treatment: { name: 'DC - Initial', length: 40, price: 120.00 },
      datetime: "#{TODAY} 12:00PM"
    )

    get '/admin/schedule/'
    doc = Nokogiri::HTML(last_response.body)

    # Assert that there are two discipline <li> items: Physiotherapy and Chiro
    discipline_list = doc.at_css('ul.discipline-list')
    disciplines = discipline_list.css('>li').map(&:text)

    assert_equal(2, disciplines.size)
    
    ['Physiotherapy', 'Chiropractic'].each do |discipline| 
      assert_includes(last_response.body, discipline)
    end
  end

  ##############
  # Staff CRUD #
  ##############
  def test_admin_view_all_staff
    staff_names = ['Annie Hu', 'Hugo Ma', 'Kevin Ho', 'Alan Mitri']
    staff_names.each do |name|
      user_id = return_id(create_user(name))
      create_profile(user_id, type: 'staff')
    end

    get '/admin/staff'
    doc = Nokogiri::HTML(last_response.body)    
    staff_listings = doc.css('ul.staff-list > li').map(&:text)

    # Assert there is an <li> element for each name in /staff
    assert_equal(staff_names.size, staff_listings.size)
    staff_names.each { |name| staff_listings.join.include?(name) }
  end

  private

  #################################################
  # Helpers for generating test data before tests #
  #################################################
  
  # Create an appointment along with any necessary join data
  def create_appointment_cascade(staff:, patient:, discipline:, treatment:, datetime:)
    staff_id = staff[:id]     || return_id(create_user(staff[:name]))
    create_profile(staff_id, type: 'staff') if staff[:create_profile]
  
    patient_id = patient[:id] || return_id(create_user(patient[:name]))
    create_profile(patient_id) if patient[:create_profile]

    discipline_id = discipline[:id] || return_id(create_discipline(discipline[:name], discipline[:title]))
  
    create_staff_discipline_association(staff_id, discipline_id) unless staff[:id] && discipline[:id]
    
    treatment_id = treatment[:id]   || return_id(create_treatment(treatment[:name], discipline_id, 
                                                                  treatment[:length], treatment[:price]))
    create_appointment(staff_id, patient_id, treatment_id, datetime)

    # Return the IDs of the created objects for subsequent use
    { staff_id: staff_id, patient_id: patient_id, 
      discipline_id: discipline_id, treatment_id: treatment_id }
  end

  # Return the ID from a PG::Result object
  def return_id(result)
    result.first['id'].to_i  
  end

  # Create a dummy appointment
  def create_appointment(staff_id, patient_id, treatment_id, datetime)
    sql = "INSERT INTO appointments(staff_id, patient_id, treatment_id, datetime)
           VALUES($1, $2, $3, $4);"
    @storage.query(sql, staff_id, patient_id, treatment_id, datetime)
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
  def create_discipline(name, title = '', clinical: true)
    sql = "INSERT INTO disciplines (name, title, clinical)
           VALUES($1, $2, $3) RETURNING *;"
    @storage.query(sql, name, title, clinical)
  end

  # Create a dummy treatment type
  def create_treatment(name, discipline_id, length, price)
    sql = "INSERT INTO treatments (name, discipline_id, length, price)
           VALUES($1, $2, $3, $4) RETURNING *;"
    @storage.query(sql, name, discipline_id, length, price)
  end

  # Create a staff-discipline M-M association
  def create_staff_discipline_association(staff_id, discipline_id)
    sql = "INSERT INTO staff_disciplines (staff_id, discipline_id)
           VALUES($1, $2);"
    @storage.query(sql, staff_id, discipline_id)
  end
end