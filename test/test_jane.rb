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
      create_staff_profile(user_id)
    end

    get '/admin/staff'
    doc = Nokogiri::HTML(last_response.body)    
    staff_listings = doc.css('ul.staff-list > li').map(&:text)

    # Assert there is an <li> element for each name in /staff
    assert_equal(staff_names.size, staff_listings.size)
    staff_names.each { |name| staff_listings.join.include?(name) }
  end

  def test_admin_view_staff_member_all_fields
    discipline_id = return_id(create_discipline('Physiotherapy', 'PT'))
    user_id = return_id(create_user('Annie Hu', 
                                     email: 'hu_annie06@gmail.com',
                                     phone: 6476089210))
    create_staff_profile(user_id, biography: 'Annie!')
    create_staff_discipline_association(user_id, discipline_id)

    get "/admin/staff/#{user_id}"
    doc = Nokogiri::HTML(last_response.body)

    name_field = doc.at_xpath("//p[strong[contains(text(), 'Name:')]]").text
    assert_equal('Name: Annie Hu', name_field)

    discipline_field = doc.at_xpath("//p[strong[contains(text(), 'Disciplines:')]]").text
    assert_includes(discipline_field, 'Physiotherapy')

    email_field = doc.at_xpath("//p[strong[contains(text(), 'Email:')]]").text
    assert_equal('Email: hu_annie06@gmail.com', email_field)

    phone_field = doc.at_xpath("//p[strong[contains(text(), 'Phone Number:')]]").text
    assert_equal('Phone Number: 6476089210', phone_field)

    bio_field = doc.at_xpath("//p[strong[contains(text(), 'Bio:')]]").text
    assert_equal('Bio: Annie!', bio_field)
  end

  def test_admin_view_staff_member_multiple_disciplines
    physio_id = return_id(create_discipline('Physiotherapy', 'PT'))
    chiro_id = return_id(create_discipline('Chiropractic', 'DC'))
    user_id = return_id(create_user('Quinn Powell-Jones', 
                                     email: 'quinn@gmail.com',
                                     phone: 4167891234))
    create_staff_profile(user_id, biography: "Hi I'm Quinn I'm a physio and chiro nice to meet you!")
    create_staff_discipline_association(user_id, physio_id)
    create_staff_discipline_association(user_id, chiro_id)

    get "/admin/staff/#{user_id}"
    doc = Nokogiri::HTML(last_response.body)

    discipline_field = doc.at_xpath("//p[strong[contains(text(), 'Disciplines:')]]").text
    assert_includes(discipline_field, 'Physiotherapy, Chiropractic')
  end

  def test_admin_view_staff_member_missing_optional_fields
    user_id = return_id(create_user('Annie Hu'))
    create_staff_profile(user_id)

    get "/admin/staff/#{user_id}"
    doc = Nokogiri::HTML(last_response.body)

    email_field = doc.at_xpath("//p[strong[contains(text(), 'Email:')]]").text
    assert_equal('Email: No Email Address', email_field)

    phone_field = doc.at_xpath("//p[strong[contains(text(), 'Phone Number:')]]").text
    assert_equal('Phone Number: No Phone Number', phone_field)

    # Bio does not show up if biography is nil
    bio_field = doc.at_xpath("//p[strong[contains(text(), 'Bio:')]]")
    assert_nil(bio_field)
  end

  def test_admin_create_staff_member_missing_name_error
    pt_id = return_id(create_discipline('Physiotherapy', 'PT')).to_s
    mt_id = return_id(create_discipline('Massage Therapy', 'MT')).to_s

    post '/admin/staff/new', first_name: '', last_name: '',
      discipline_ids: [pt_id, mt_id], email: 'hgm@gmail.com', phone: '6476758914',
      biography: 'Hello I am under the water'
    
    doc = Nokogiri::HTML(last_response.body) 

    # Error messages are present
    assert_includes(last_response.body, 'Please enter a first name.')
    assert_includes(last_response.body, 'Please enter a last name.')

    # Fields retain values
    ['Physiotherapy', 'Massage Therapy'].each do |discipline|
      # Assert that there IS a checked label for each selected discipline
      checked_label = doc.at_css('input[checked] + label[text()="' + discipline + '"]')

      refute_nil(checked_label)
    end

    assert_includes(last_response.body, 'hgm@gmail.com')
    assert_includes(last_response.body, '6476758914')
    assert_includes(last_response.body, 'Hello I am under the water')
  end

  def test_admin_create_staff_member_strips_empty_names
    post '/admin/staff/new', first_name: '  ', last_name: 'Ma'

    assert_includes(last_response.body, 'Please enter a first name.')
  end

  def test_admin_create_staff_member_success_all_fields_given
    pt_id = return_id(create_discipline('Physiotherapy', 'PT')).to_s
    dc_id = return_id(create_discipline('Chiropractic', 'DC')).to_s

    # Baseline: Empty DB
    users_count = @storage.query("SELECT * FROM users;").ntuples
    staff_count = @storage.query("SELECT * FROM staff;").ntuples
    staff_disciplines_count = @storage.query("SELECT * FROM staff_disciplines").ntuples
    
    assert_equal(0, users_count)
    assert_equal(0, staff_count)
    assert_equal(0, staff_disciplines_count)
    
    # Submit POST Request
    post '/admin/staff/new', first_name: 'Annie', last_name: 'Hu',
      email: 'annie@gmail.com', phone: '6479059550', biography: 'Annie!',
      discipline_ids: [pt_id, dc_id]
    
    # Redirects
    assert_equal(302, last_response.status)

    # Modifies DB: Users
    users_result = @storage.query("SELECT * FROM users;")
    new_users_count = users_result.ntuples
    new_user = users_result.first

    assert_equal(1, new_users_count)
    assert_equal('Annie', new_user['first_name'])
    assert_equal('Hu', new_user['last_name'])
    assert_equal('annie@gmail.com', new_user['email'])
    assert_equal('6479059550', new_user['phone'])
    
    # Modifies DB: Staff
    staff_result = @storage.query("SELECT * FROM staff;")
    new_staff_count = staff_result.ntuples
    new_staff = staff_result.first

    assert_equal(1, new_staff_count)
    assert_equal('Annie!', new_staff['biography'])

    # Modifies DB: Staff Disciplines (2 - PT and DC)
    staff_disciplines_result = @storage.query("SELECT * FROM staff_disciplines;")
    staff_disciplines_count = staff_disciplines_result.ntuples
    discipline_ids = staff_disciplines_result.map { |row| row['discipline_id'] }
    
    assert_equal(2, staff_disciplines_count)
    assert_equal([pt_id, dc_id].sort, discipline_ids.sort)
  end

  def test_admin_edit_staff_member_empty_or_missing_name_error
    # Create a staff member
    user_id = return_id(create_user('Phil Genesis'))
    create_staff_profile(user_id)
    
    # Edit the staff member (without names)
    post "/admin/staff/#{user_id}/edit", first_name: ' ', last_name: nil

    assert_includes(last_response.body, 'Please enter a first name.')
    assert_includes(last_response.body, 'Please enter a last name.')
  end

  def test_admin_edit_staff_nonexistent_record_error_redirects
    user_id = return_id(create_user('Phil Genesis'))
    create_staff_profile(user_id)
    bad_user_id = user_id + 1
    
    post "/admin/staff/#{bad_user_id}/edit", first_name: 'Phillip', last_name: 'Genesis'
    # Follow the redirect
    get last_response['location']

    assert_includes(last_response.body, "(id = #{bad_user_id}) could not be found.")
  end

  private

  #################################################
  # Helpers for generating test data before tests #
  #################################################
  
  # Create an appointment along with any necessary join data
  def create_appointment_cascade(staff:, patient:, discipline:, treatment:, datetime:)
    staff_id = staff[:id]     || return_id(create_user(staff[:name]))
    create_staff_profile(staff_id) if staff[:create_profile]
  
    patient_id = patient[:id] || return_id(create_user(patient[:name]))
    create_patient_profile(patient_id) if patient[:create_profile]

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
  def create_user(name, email: nil, phone: nil)
    first_name, last_name = name.split
    
    sql = "INSERT INTO users(first_name, last_name, email, phone) 
           VALUES($1, $2, $3, $4) RETURNING *;"
    @storage.query(sql, first_name, last_name, email, phone)
  end

  # Create a dummy profile (staff/patient)
  def create_staff_profile(user_id, biography: nil)
    sql = "INSERT INTO staff VALUES ($1, $2) RETURNING *;"
    @storage.query(sql, user_id, biography)
  end

  def create_patient_profile(user_id, birthday: nil)
    sql = "INSERT INTO patients (user_id, birthday) VALUES ($1, $2) RETURNING *;"
    @storage.query(sql, user_id, birthday)
  end

  # Create a dummy discipline
  def create_discipline(name, title = nil)
    sql = "INSERT INTO disciplines (name, title)
           VALUES($1, $2) RETURNING *;"
    @storage.query(sql, name, title)
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