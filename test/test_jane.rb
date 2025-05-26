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
  
  # Admin Schedule Page #
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

  # Staff CRUD #
  def test_admin_view_all_staff
    staff_names = ['Annie Hu', 'Hugo Ma', 'Kevin Ho', 'Alan Mitri']
    staff_names.each do |name|
      user_id = return_id(create_user(name))
      create_staff_member(user_id)
    end

    get '/admin/staff'
    doc = Nokogiri::HTML(last_response.body)    
    staff_listings = doc.css('ul.staff-list > li')

    # Assert there is an <li> element for each name in /staff
    assert_equal(staff_listings.size, staff_names.size)

    staff_names.each do |name|
      staff_li = staff_listings.find { |li| li.text.include?(name) }
      refute_nil(staff_li)
    end
  end

  def test_admin_view_staff_member_all_fields
    discipline_id = return_id(create_discipline('Physiotherapy', 'PT'))
    user_id = return_id(create_user('Annie Hu', 
                                     email: 'hu_annie06@gmail.com',
                                     phone: 6476089210))
    create_staff_member(user_id, biography: 'Annie!')
    create_staff_discipline_associations(user_id, discipline_id)

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
    create_staff_member(user_id, biography: "Hi I'm Quinn I'm a physio and chiro nice to meet you!")
    create_staff_discipline_associations(user_id, physio_id, chiro_id)

    get "/admin/staff/#{user_id}"
    doc = Nokogiri::HTML(last_response.body)

    discipline_field = doc.at_xpath("//p[strong[contains(text(), 'Disciplines:')]]").text
    assert_includes(discipline_field, 'Physiotherapy, Chiropractic')
  end

  def test_admin_view_staff_member_missing_optional_fields
    user_id = return_id(create_user('Annie Hu'))
    create_staff_member(user_id)

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
    create_staff_member(user_id)
    
    # Edit the staff member (without names)
    post "/admin/staff/#{user_id}/edit", first_name: ' ', last_name: nil

    assert_includes(last_response.body, 'Please enter a first name.')
    assert_includes(last_response.body, 'Please enter a last name.')
  end

  def test_admin_edit_staff_nonexistent_record_error_redirects
    user_id = return_id(create_user('Phil Genesis'))
    create_staff_member(user_id)
    bad_user_id = user_id + 1
    
    post "/admin/staff/#{bad_user_id}/edit", first_name: 'Phillip', last_name: 'Genesis'
    # Follow the redirect
    get last_response['location']

    assert_includes(last_response.body, "(id = #{bad_user_id}) could not be found.")
  end

  def test_admin_edit_staff_updates_users_record
    user_id = return_id(create_user('Anie H', email: 'hu_annie@gmail.com'))
    create_staff_member(user_id)
    user = @storage.query("SELECT * FROM users WHERE id = $1", user_id).first
    
    assert_equal('Anie', user['first_name'])
    assert_equal('H', user['last_name'])
    assert_equal('hu_annie@gmail.com', user['email'])
    
    post "/admin/staff/#{user_id}/edit", 
      first_name: 'Annie', last_name: 'Hu', email: 'hu_annie06@gmail.com'
    
    updated_user = @storage.query("SELECT * FROM users WHERE id = $1", user_id).first

    assert_equal('Annie', updated_user['first_name'])
    assert_equal('Hu', updated_user['last_name'])
    assert_equal('hu_annie06@gmail.com', updated_user['email'])
  end

  def test_admin_edit_staff_updates_staff_record
    user_id = return_id(create_user('Annie Hu'))
    create_staff_member(user_id, biography: 'placeholder bio')
    staff = @storage.query("SELECT * FROM staff WHERE user_id = $1", user_id).first

    assert_equal('placeholder bio', staff['biography'])
    
    post "/admin/staff/#{user_id}/edit", 
      first_name: 'Annie', last_name: 'Hu', biography: 'New biography!'

    updated_staff = @storage.query("SELECT * FROM staff WHERE user_id = $1", user_id).first
    assert_equal('New biography!', updated_staff['biography'])
  end

  def test_admin_edit_staff_overwrites_staff_disciplines_records
    pt_id = return_id(create_discipline('Physiotherapy', 'PT')).to_s
    mt_id = return_id(create_discipline('Massage Therapy', 'MT')).to_s
    dc_id = return_id(create_discipline('Chiropractic', 'DC')).to_s
    user_id = return_id(create_user('Annie Hu'))
    create_staff_member(user_id)
    create_staff_discipline_associations(user_id, pt_id, dc_id)

    sd = @storage.query("SELECT * FROM staff_disciplines WHERE staff_id = $1", user_id)
    discipline_ids = sd.map { |row| row['discipline_id'] }
    
    assert_equal(2, discipline_ids.size)
    assert_equal([pt_id, dc_id].sort, discipline_ids.sort)

    post "/admin/staff/#{user_id}/edit", first_name: 'Annie', last_name: 'Hu',
      discipline_ids: [pt_id, mt_id]

    sd = @storage.query("SELECT * FROM staff_disciplines WHERE staff_id = $1", user_id)
    new_discipline_ids = sd.map { |row| row['discipline_id'] }

    assert_equal(2, new_discipline_ids.size)
    assert_equal([pt_id, mt_id].sort, new_discipline_ids.sort)
  end

  def test_admin_edit_staff_success_redirects_to_staff_profile
    user_id = return_id(create_user('Annie Hu'))
    create_staff_member(user_id)

    post "/admin/staff/#{user_id}/edit", first_name: 'Annie', last_name: 'Hu'

    assert_equal(302, last_response.status)
    get last_response['location']
    doc = Nokogiri::HTML(last_response.body)

    name_field = doc.at_xpath("//p[strong[contains(text(), 'Name:')]]").text
    assert_equal('Name: Annie Hu', name_field)
  end

  def test_admin_delete_staff_success_delete_cascades
    pt_id = return_id(create_discipline('Physiotherapy', 'PT'))
    user_id = return_id(create_user('Phil Genesis'))
    create_staff_member(user_id)
    create_staff_discipline_associations(user_id, pt_id)

    user = @storage.query("SELECT * FROM users WHERE id = $1", user_id).first
    staff = @storage.query("SELECT * FROM staff WHERE user_id = $1", user_id).first
    sd = @storage.query("SELECT * FROM staff_disciplines WHERE staff_id = $1", user_id).first
    
    refute_nil(user)
    refute_nil(staff)
    refute_nil(sd)

    post "/admin/staff/#{user_id}/delete"

    user = @storage.query("SELECT * FROM users WHERE id = $1", user_id).first
    staff = @storage.query("SELECT * FROM staff WHERE user_id = $1", user_id).first
    sd = @storage.query("SELECT * FROM staff_disciplines WHERE staff_id = $1", user_id).first
    
    assert_nil(user)
    assert_nil(staff)
    assert_nil(sd)
  end

  def test_admin_delete_staff_redirects_to_staff
    user_id = return_id(create_user('Phil Genesis'))
    create_staff_member(user_id)

    post "/admin/staff/#{user_id}/delete"
    
    assert_equal(302, last_response.status)
  end

  # # Patients CRUD # # 
  def test_admin_view_all_patients
    patient_names = ['Hugo Ma', 'Hendrik Swart']

    patient_names.each do |name|
      user_id = return_id(create_user(name))
      create_patient_profile(user_id)
    end

    get '/admin/patients'
    doc = Nokogiri::HTML(last_response.body)
    patients_listings = doc.css('ul.patients-list > li')

    assert_equal(patient_names.size, patients_listings.size)

    patient_names.each do |name|
      patient_li = patients_listings.find { |li| li.text.include?(name) }
      refute_nil(patient_li)
    end
  end

  def test_admin_view_patient_basic_info_fields
    name = 'Hugo Ma'
    phone = '6476758914'
    email = 'h@gmail.com'
    birthday = '1997-09-14'

    patient_id = return_id(create_user(name, email: email, phone: phone))
    create_patient_profile(patient_id, birthday: birthday)

    get "/admin/patients/#{patient_id}"
    doc = Nokogiri::HTML(last_response.body)

    # Total Appointments: 0
    appts_field = doc.at_xpath("//div[contains(text(), 'Total Appointments')]")
    assert_includes(appts_field.text, '0')
    # Name: Hugo Ma
    name_field = doc.at_xpath("//p[strong[contains(text(), 'Name')]]")
    assert_includes(name_field.text, name)
    # Phone: 6476758914
    phone_field = doc.at_xpath("//p[strong[contains(text(), 'Phone')]]")
    assert_includes(phone_field.text, phone)
    # Email: h@gmail.com
    email_field = doc.at_xpath("//p[strong[contains(text(), 'Email')]]")
    assert_includes(email_field.text, email)
    # Birthday: 1997-09-14
    bday_field = doc.at_xpath("//p[strong[contains(text(), 'Birthday')]]")
    assert_includes(bday_field.text, birthday)
  end

  def test_admin_view_patient_appt_count_increments
    patient_id = return_id(create_user('Hugo Ma', 
      email: 'h@gmail.com', phone: '6476758914'))
    create_patient_profile(patient_id, birthday: '1997-09-14')
    # Appt 1
    context = create_appointment_cascade(
      staff: { name: 'Annie Hu', create_profile: true }, 
      patient: { id: patient_id, create_profile: false },
      discipline: { name: 'Physiotherapy', title: 'PT' },
      treatment: { name: 'PT - Initial', length: 45, price: 100.00 }
    )
    # Appt 2
    create_appointment_cascade(
      staff: { id: context[:staff_id] }, 
      patient: { id: patient_id, create_profile: false },
      discipline: { id: context[:discipline_id] },
      treatment: { name: 'PT - Treatment', length: 30, price: 85.00 }
    )

    get "/admin/patients/#{patient_id}"
    doc = Nokogiri::HTML(last_response.body)

    appts_field = doc.at_xpath("//div[contains(text(), 'Total Appointments')]")
    assert_includes(appts_field.text, '2')
  end

  def test_admin_view_patient_calculates_and_formats_age_display
    today = Date.today
    three_years_ago = today.prev_year(3).to_s
    three_months_ago = today.prev_month(3).to_s
    three_days_ago = today.prev_day(3).to_s

    old_patient_id = return_id(create_user('Hugo Ma'))
    create_patient_profile(old_patient_id, birthday: three_years_ago)

    baby_patient_id = return_id(create_user('Jonas C'))
    create_patient_profile(baby_patient_id, birthday: three_months_ago)

    newborn_patient_id = return_id(create_user('Tanya T'))
    create_patient_profile(newborn_patient_id, birthday: three_days_ago)

    # Years
    get "/admin/patients/#{old_patient_id}"
    doc = Nokogiri::HTML(last_response.body)
    age_field = doc.at_xpath("//p[strong[text()='Age:']]")
    assert_includes(age_field.text, '3 years')
    # Months
    get "/admin/patients/#{baby_patient_id}"
    doc = Nokogiri::HTML(last_response.body)
    age_field = doc.at_xpath("//p[strong[text()='Age:']]")
    assert_includes(age_field.text, '3 months')
    # Days
    get "/admin/patients/#{newborn_patient_id}"
    doc = Nokogiri::HTML(last_response.body)
    age_field = doc.at_xpath("//p[strong[text()='Age:']]")
    assert_includes(age_field.text, '3 days')
  end

  def test_admin_view_patient_redirects_nonexistent_id
    bad_id = 5
    get "/admin/patients/#{bad_id}"

    assert_equal(302, last_response.status)
  end

  def test_admin_view_patient_hides_birthday_and_age_if_nil
    patient_id = return_id(create_user('Hugo Ma'))
    create_patient_profile(patient_id, birthday: nil)

    get "/admin/patients/#{patient_id}"
    doc = Nokogiri::HTML(last_response.body)
    birthday_field = doc.at_xpath("//p[strong[text()='Birthday:']]")
    age_field = doc.at_xpath("//p[strong[text()='Age:']]")

    assert_nil(birthday_field)
    assert_nil(age_field)
  end

  def test_admin_create_patient_success
    users_count = @storage.query("SELECT * FROM users;").ntuples
    patients_count = @storage.query("SELECT * FROM patients;").ntuples

    assert_equal(0, users_count)
    assert_equal(0, patients_count)

    post '/admin/patients/new', first_name: 'Hugo', last_name: 'Ma'
    users_result = @storage.query("SELECT * FROM users;")
    patients_result = @storage.query("SELECT * FROM patients;")

    assert_equal(1, users_result.ntuples)
    assert_equal(1, patients_result.ntuples)
    assert_equal('Hugo', users_result.first['first_name'])
    
    assert_equal(302, last_response.status)
  end

  def test_admin_create_patient_handles_empty_birthday
    users_count = @storage.query("SELECT * FROM users;").ntuples
    patients_count = @storage.query("SELECT * FROM patients;").ntuples

    assert_equal(0, users_count)
    assert_equal(0, patients_count)

    post '/admin/patients/new', first_name: 'Hugo', last_name: 'Ma',
      birthday: '' # Empty Birthday Input
    
    users_count = @storage.query("SELECT * FROM users;").ntuples
    patients_count = @storage.query("SELECT * FROM patients;").ntuples

    assert_equal(1, users_count)
    assert_equal(1, patients_count)
  end

  def test_admin_create_patient_empty_missing_name_error
    post '/admin/patients/new', first_name: ' '

    assert_includes(last_response.body, 'Please enter a first name.')
    assert_includes(last_response.body, 'Please enter a last name.')
  end

  def test_admin_create_patient_retains_values_on_error
    first_name = 'Hugo'
    email = 'hugoma@gmail.com'
    phone = '6476754903'
    birthday = '1997-09-14'

    post '/admin/patients/new', first_name: first_name, last_name: '',
      email: email, phone: phone, birthday: birthday  
    doc = Nokogiri::HTML(last_response.body)
    
    # First Name
    first_name_input = doc.at_xpath("//input[@id='first_name']")
    assert_equal(first_name, first_name_input['value'])
    # Email
    email_input = doc.at_xpath("//input[@id='email']")
    assert_equal(email, email_input['value'])
    # Phone
    phone_input = doc.at_xpath("//input[@id='phone']")
    assert_equal(phone, phone_input['value'])
    # Birthday
    birthday_input = doc.at_xpath("//input[@id='birthday']")
    assert_equal(birthday, birthday_input['value'])
  end

  def test_admin_edit_patient_success
    user_id = return_id(create_user('Huugo Ma', 
                         email: 'hgm@gmail.com', phone: '6476758913'))
    create_patient_profile(user_id, birthday: '1997-09-15')

    user_patient = @storage.query(
      "SELECT * FROM users 
       JOIN patients ON users.id = patients.user_id
       WHERE users.id = $1", user_id).first

    assert_equal('Huugo', user_patient['first_name'])
    assert_equal('hgm@gmail.com', user_patient['email'])
    assert_equal('6476758913', user_patient['phone'])
    assert_equal('1997-09-15', user_patient['birthday'])

    post "/admin/patients/#{user_id}/edit", first_name: 'Hugo', last_name: 'Ma', 
      email: 'huwgoma@gmail.com', phone: '6476758914', birthday: '1997-09-14'
    
    user_patient = @storage.query(
      "SELECT * FROM users 
       JOIN patients ON users.id = patients.user_id
       WHERE users.id = $1", user_id).first

    assert_equal('Hugo', user_patient['first_name'])
    assert_equal('huwgoma@gmail.com', user_patient['email'])
    assert_equal('6476758914', user_patient['phone'])
    assert_equal('1997-09-14', user_patient['birthday'])
   
    assert_equal(302, last_response.status)
  end

  def test_admin_edit_patient_handles_empty_birthday
    user_id = return_id(create_user('Huugo Ma', 
                         email: 'hgm@gmail.com', phone: '6476758913'))
    create_patient_profile(user_id, birthday: '1997-09-15')

    patient = @storage.query("SELECT * FROM patients WHERE user_id = $1", user_id).first
    assert_equal('1997-09-15', patient['birthday'])

    post "/admin/patients/#{user_id}/edit", first_name: 'Hugo', last_name: 'Ma',
      birthday: '' # Empty Birthday
    
    patient = @storage.query("SELECT * FROM patients WHERE user_id = $1", user_id).first
    assert_nil(patient['birthday'])
  end

  def test_admin_edit_patient_empty_missing_name_error
    user_id = return_id(create_user('Hugo Ma'))
    create_patient_profile(user_id)

    post "/admin/patients/#{user_id}/edit", first_name: ' '

    assert_includes(last_response.body, 'Please enter a first name.')
    assert_includes(last_response.body, 'Please enter a last name.')
  end

  def test_admin_edit_patient_retains_values_on_error
    email = 'hugoma@gmail.com'
    phone = '6476754903'
    birthday = '1997-09-14'

    user_id = return_id(create_user('Huugo Ma', email: email, phone: phone))
    create_patient_profile(user_id, birthday: birthday)

    post "/admin/patients/#{user_id}/edit", first_name: 'Hugo',
      last_name: '', email: email, phone: phone, birthday: birthday
    doc = Nokogiri::HTML(last_response.body)
    
    # First Name
    first_name_input = doc.at_xpath("//input[@id='first_name']")
    assert_equal('Hugo', first_name_input['value'])
    # Email
    email_input = doc.at_xpath("//input[@id='email']")
    assert_equal(email, email_input['value'])
    # Phone
    phone_input = doc.at_xpath("//input[@id='phone']")
    assert_equal(phone, phone_input['value'])
    # Birthday
    birthday_input = doc.at_xpath("//input[@id='birthday']")
    assert_equal(birthday, birthday_input['value'])
  end

  def test_admin_delete_patient_success_delete_cascades
    # Verifies delete of both user and patient
    user_id = return_id(create_user('Hugo Ma'))
    create_patient_profile(user_id)

    users_count = @storage.query("SELECT 1 FROM users WHERE id = $1", user_id).ntuples
    patients_count = @storage.query("SELECT 1 FROM patients WHERE user_id = $1", user_id).ntuples

    assert_equal(1, users_count)
    assert_equal(1, patients_count)

    post "/admin/patients/#{user_id}/delete"

    users_count = @storage.query("SELECT 1 FROM users WHERE id = $1", user_id).ntuples
    patients_count = @storage.query("SELECT 1 FROM patients WHERE user_id = $1", user_id).ntuples

    assert_equal(0, users_count)
    assert_equal(0, patients_count)
  end

  def test_admin_delete_patient_success_redirects_to_patients
    user_id = return_id(create_user('Hugo Ma'))
    create_patient_profile(user_id)

    post "/admin/patients/#{user_id}/delete"

    assert_equal(302, last_response.status)
    get last_response['location']
    assert_includes(last_response.body, 'successfully deleted.')
  end

  # # SETTINGS # # 
  # - Disciplines
  def test_admin_view_disciplines_practitioner_counts
    annie_id = return_id(create_user('Annie Hu'))
    create_staff_member(annie_id)
    kevin_id = return_id(create_user('Kevin Ho'))
    create_staff_member(kevin_id)
    alexis_id = return_id(create_user('Alexis Butler'))
    create_staff_member(alexis_id)

    pt_id = return_id(create_discipline('Physiotherapy', 'PT'))
    dc_id = return_id(create_discipline('Chiropractic', 'DC'))
    create_discipline('Massage Therapy', 'MT')

    create_staff_discipline_associations(annie_id, pt_id)
    create_staff_discipline_associations(kevin_id, pt_id)
    create_staff_discipline_associations(alexis_id, dc_id)

    get '/admin/disciplines'
    doc = Nokogiri::HTML(last_response.body)
    pt_listing = doc.at_xpath("//li[h4[text()='Physiotherapy']]")
    dc_listing = doc.at_xpath("//li[h4[text()='Chiropractic']]")
    mt_listing = doc.at_xpath("//li[h4[text()='Massage Therapy']]")
    
    assert_includes(pt_listing.text, '2 Staff Members')
    assert_includes(dc_listing.text, '1 Staff Members')
    assert_includes(mt_listing.text, '0 Staff Members')
  end

  def test_admin_create_discipline_success
    disciplines_result = @storage.query("SELECT * FROM disciplines;")
    assert_equal(0, disciplines_result.ntuples)

    post '/admin/disciplines/new', name: 'Physiotherapy', title: 'PT'

    disciplines_result = @storage.query("SELECT * FROM disciplines;")
    discipline = disciplines_result.first

    assert_equal(1, disciplines_result.ntuples)
    assert_equal('Physiotherapy', discipline['name'])
    assert_equal('PT', discipline['title'])

    assert_equal(302, last_response.status)
  end

  def test_admin_create_discipline_error_empty_name_or_title
    post '/admin/disciplines/new', name: '' # Missing Title

    assert_includes(last_response.body, 'Please enter a name.')
    assert_includes(last_response.body, 'Please enter a title.')
  end

  def test_admin_create_discipline_error_duplicate_name
    create_discipline('Physiotherapy', 'PT')

    post '/admin/disciplines/new', name: 'Physiotherapy', title: 'PT'

    assert_includes(last_response.body, 
      'Another discipline named Physiotherapy already exists.')
  end

  def test_admin_create_discipline_retains_values_on_error
    post "/admin/disciplines/new", name: 'Physiotherapy', title: ''
    doc = Nokogiri::HTML(last_response.body)
    name_input = doc.at_xpath("//input[@id='name']")
    
    assert_equal('Physiotherapy', name_input['value'])
   
    post "/admin/disciplines/new", name: '', title: 'PT'
    doc = Nokogiri::HTML(last_response.body)
    title_input = doc.at_xpath("//input[@id='title']")
    
    assert_equal('PT', title_input['value'])
  end

  def test_admin_edit_discipline_success
    pt_id = return_id(create_discipline('Physio', 'pt'))
    record = @storage.query("SELECT * FROM disciplines WHERE id = $1", pt_id).first

    assert_equal('Physio', record['name'])
    assert_equal('pt', record['title'])

    post "/admin/disciplines/#{pt_id}/edit", name: 'Physiotherapy', title: 'PT'
    updated_record = @storage.query("SELECT * FROM disciplines WHERE id = $1", pt_id).first

    assert_equal('Physiotherapy', updated_record['name'])
    assert_equal('PT', updated_record['title'])

    assert_equal(302, last_response.status)
    get last_response['location']
    assert_includes(last_response.body, 'Discipline successfully updated.')
  end

  def test_admin_edit_discipline_redirects_missing_or_nil_id
    bad_id = 5
    post "/admin/disciplines/#{bad_id}/edit"

    assert_equal(302, last_response.status)
    get last_response['location']
    assert_includes(last_response.body, 'could not be found')
  end

  def test_admin_edit_discipline_error_empty_name_or_title
    pt_id = return_id(create_discipline('Physio', 'Pt'))

    # Empty name, missing title
    post "/admin/disciplines/#{pt_id}/edit", name: ''

    assert_includes(last_response.body, 'Please enter a name.')
    assert_includes(last_response.body, 'Please enter a title.')
  end

  def test_admin_edit_discipline_error_duplicate_name
    pt_id = return_id(create_discipline('Physiotherapy', 'PT'))
    create_discipline('Chiropractic', 'DC')

    post "/admin/disciplines/#{pt_id}/edit", name: 'Chiropractic', title: 'DC'

    assert_includes(last_response.body,
      "Another discipline named Chiropractic already exists.")
  end

  def test_admin_edit_discipline_retains_values_on_error
    pt_id = return_id(create_discipline('Physio', 'P'))

    post "/admin/disciplines/#{pt_id}/edit", name: 'Physiotherapy', title: ''
    doc = Nokogiri::HTML(last_response.body)

    name_input = doc.at_xpath("//input[@id='name']")
    assert_equal('Physiotherapy', name_input['value'])

    post "/admin/disciplines/#{pt_id}/edit", name: '', title: 'PT'
    doc = Nokogiri::HTML(last_response.body)

    title_input = doc.at_xpath("//input[@id='title']")
    assert_equal('PT', title_input['value'])
  end

  # - Treatments
  def test_admin_view_treatments_ordered_by_discipline
    pt_id = return_id(create_discipline('Physiotherapy', 'PT'))
    mt_id = return_id(create_discipline('Massage Therapy', 'MT'))

    create_treatment('PT - Initial', pt_id, 45, 100.00)
    create_treatment('PT - Treatment', pt_id, 30, 85.00)
    create_treatment('MT - 30 Minutes', mt_id, 30, 75.00)

    get '/admin/treatments'
    doc = Nokogiri::HTML(last_response.body)

    pt_ol = doc.at_xpath("//h4[text()='Physiotherapy']/following-sibling::ol")
    mt_ol = doc.at_xpath("//h4[text()='Massage Therapy']/following-sibling::ol")

    assert_includes(pt_ol.text, 'PT - Initial')
    assert_includes(pt_ol.text, 'PT - Treatment')
    assert_includes(mt_ol.text, 'MT - 30 Minutes')
  end

  def test_admin_create_treatment_success
    pt_id = return_id(create_discipline('Physio', 'PT'))
    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples
    assert_equal(0, treatments_count)

    post '/admin/treatments/new', name: 'PT - Tx', discipline_id: pt_id,
      length: 30, price: 100.00

    treatments_result = @storage.query("SELECT * FROM treatments;")
    treatment = treatments_result.first
    assert_equal(1, treatments_result.ntuples)
    assert_equal('PT - Tx', treatment['name'])
    assert_equal(pt_id.to_s, treatment['discipline_id'])
    assert_equal('30', treatment['length'])
    assert_equal('$100.00', treatment['price'])

    assert_equal(302, last_response.status)
    get last_response['location']

    assert_includes(last_response.body, 'Successfully created treatment')
  end

  def test_admin_create_treatment_error_all_fields_required
    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)

    post '/admin/treatments/new', discipline_id: '', name: '',
      length: '', price: ''

    assert_includes(last_response.body, 'Please enter a name.')
    assert_includes(last_response.body, 'Please enter a price.')
    assert_includes(last_response.body, 'Please select a valid length.')
    assert_includes(last_response.body, 'does not match any existing disciplines.')
    
    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)

  end

  def test_admin_create_treatment_error_negative_price
    pt_id = return_id(create_discipline('Physio', 'PT'))  

    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples

    post '/admin/treatments/new', name: 'Test', discipline_id: pt_id,
      length: 30, price: -10

    new_treatments_count = @storage.query("SELECT * FROM treatments;").ntuples
    assert_equal(new_treatments_count, treatments_count)
    assert_includes(last_response.body, 'Please enter a non-negative price.')
  end

  def test_admin_create_treatment_discipline_id_must_exist
    pt_id = return_id(create_discipline('Physio', 'PT'))
    bad_discipline_id = pt_id + 1

    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)

    post 'admin/treatments/new', name: 'Test', discipline_id: bad_discipline_id,
      length: 45, price: 100.00

    assert_includes(last_response.body, 'does not match any existing disciplines.')

    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)

  end

  def test_admin_create_treatment_invalid_length_select
    pt_id = return_id(create_discipline('Physio', 'PT'))

    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)

    post 'admin/treatments/new', name: 'Test', discipline_id: pt_id,
      length: 3, price: 100.00

    assert_includes(last_response.body, 'Please select a valid length.')

    treatments_count = @storage.query("SELECT * FROM treatments;").ntuples 
    assert_equal(0, treatments_count)
  end

  def test_admin_edit_treatment_success
    # Doesnt change the number of treatment rcords
    # Edits the fields of the target treatment correctly
    # Redirects
  end

  def test_admin_edit_treatment_error_all_fields_required
    
  end

  def test_admin_edit_treatmmnt_error_discipline_id_must_exist
    
  end

  def test_admin_create_treatment_invalid_length_select
    
  end



  private

  # Helpers for generating test data before tests #
  # Create an appointment along with any necessary join data
  def create_appointment_cascade(staff:, patient:, discipline:, treatment:, datetime: DateTime.now)
    staff_id = staff[:id]     || return_id(create_user(staff[:name]))
    create_staff_member(staff_id) if staff[:create_profile]
  
    patient_id = patient[:id] || return_id(create_user(patient[:name]))
    create_patient_profile(patient_id) if patient[:create_profile]

    discipline_id = discipline[:id] || return_id(create_discipline(discipline[:name], discipline[:title]))
  
    create_staff_discipline_associations(staff_id, discipline_id) unless staff[:id] && discipline[:id]
    
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
  def create_staff_member(user_id, biography: nil)
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
  def create_staff_discipline_associations(staff_id, *discipline_ids)
    placeholders = discipline_ids.map.with_index do |id, index|
      "($1, $#{index + 2})"
    end.join(', ')

    sql = "INSERT INTO staff_disciplines (staff_id, discipline_id)
           VALUES #{placeholders};"
    @storage.query(sql, staff_id, *discipline_ids)
  end
end