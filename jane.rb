# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'
require 'date_core'
require 'active_support/inflector'

require_relative 'pg_adapter'
Dir.glob('lib/*.rb').each { |file| require_relative file }

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)

  set :erb, :escape_html => true

  set :storage, PGAdapter.new
end

configure :development do
  require 'pry'
  require 'sinatra/reloader'
  also_reload 'pg_adapter.rb', 'lib/*.rb'
end

# Helpers
helpers do
  def render_with_layout(view)
    erb view, layout: :admin_layout
  end

  # Check if a given checkbox should be pre-checked.
  # - Assumes the checkbox's value is the @id of some object.
  def prechecked?(group_name, id, params, collection=[])    
    # Check params[group_name] unless it is nil.
    params[group_name]&.include?(id.to_s) || 
      collection.any? { |obj| obj.id == id if obj.respond_to?(:id) }
  end

  def prefill(attribute, params, object=nil)
    params[attribute] || 
    (object.method(attribute).call if object.respond_to?(attribute))
  end

  # Check if a given <option> should be pre-selected.
  def preselected?(select_name, option_value, params, obj=nil)
    params[select_name] == option_value.to_s ||
      (obj.method(select_name).call == option_value if obj.respond_to?(select_name))
  end

  def pretty_duration(duration_in_minutes)
    hours, minutes = duration_in_minutes.divmod(60)

    hours_string = hours.zero? ? '' : "#{hours} #{'hour'.pluralize(hours)}"
    minutes_string = minutes.zero? ? '' : "#{minutes} #{'minute'.pluralize(minutes)}"

    "#{hours_string} #{minutes_string}"
  end

  def pretty_price(price, currency: '$')
    return '' if empty_string?(price.to_s)

    format("#{currency}%.2f", price)
  end

  def pretty_date(date)
    date.strftime('%A %B %-d, %Y')
  end

  def pretty_time(time)
    time.strftime('%l:%M%p')
  end
end

# Routes
before do
  @storage = settings.storage
  session[:errors] ||= []
  # Verify admin status and set @admin accordingly.
  # Redirect if necessary
end

not_found do
  redirect '/admin/schedule/'
end


# To Do #
# 1) Edit Appointment
# 2) Copy Appointment
# 3) Move Appointment
# 4) Delete Appointment (*)
# 5) Patient Appointments Page
# 
# --- 
# 1) extract_params
# 2) Clear DB before test suite
# 3) RESTRICT DELETE operations
# Revisit DELETEs: cascade vs. restrict


# # Admin - Schedule # #
# Redirect Date (Pretty Date URL)
get '/admin/schedule/redirect' do
  redirect "/admin/schedule/#{params[:date]}"
end

# Main Admin Schedule Page
get '/admin/schedule/?:date?/?' do
  @date = Date.parse(params[:date] || Date.today.to_s)
  @yesterday, @tomorrow = @date.prev_day, @date.next_day
  @schedule = @storage.load_daily_schedule(@date)
  
  render_with_layout(:schedule)
end

# # Admin - Appointments # # 
# Form: Create new appointment (per-practitioner)
get '/admin/appointments/new' do
  practitioner_id = params[:practitioner_id]
  @date = Date.parse(params[:date])

  redirect_if_missing_id('staff', practitioner_id, "/admin/schedule/#{@date.to_s}")
  
  @practitioner = @storage.load_staff(practitioner_id, 
    user_fields: { first_name: true, last_name: true })
  @treatments = @storage.load_treatment_listings_by_practitioner(practitioner_id)
  @patients = @storage.load_all_patients
  
  render_with_layout(:new_appointment)
end

# - Create new appointment
post '/admin/appointments/new' do
  
end


# - View a specific appointment
get '/admin/appointments/:appointment_id/?' do
  appointment_id = params[:appointment_id]

  @appointment = @storage.load_appointment_info(appointment_id)
  render_with_layout(:appointment)
end

# Form - Edit an appointment
get '/admin/appointments/:appointment_id/edit/?' do
  
end


# # Admin - Staff # #
# Form - Create new staff member
get '/admin/staff/new/?' do
  @disciplines = @storage.load_disciplines

  render_with_layout(:new_staff)
end

# Create a new staff member
post '/admin/staff/new/?' do
  first_name, last_name = params[:first_name], params[:last_name]
  
  session[:errors].push(*new_staff_errors(first_name, last_name))

  if session[:errors].any?
    @disciplines = @storage.load_disciplines
    render_with_layout(:new_staff)
  else
    email, phone, biography = params[:email], params[:phone], params[:biography]
    staff_id = @storage.create_staff_return_user_id(
                first_name, last_name, email: email, phone: phone, biography: biography)
    @storage.add_staff_disciplines(staff_id, params[:discipline_ids])

    redirect "/admin/staff/#{staff_id}"
  end
end

# View all staff
get '/admin/staff/?' do
  @staff = @storage.load_all_staff

  render_with_layout(:all_staff)
end

# View a specific staff profile
get '/admin/staff/:staff_id/?' do
  staff_id = params[:staff_id].to_i
  redirect_if_missing_id('staff', staff_id, '/admin/staff')

  @staff_profile = @storage.load_staff_profile(staff_id)

  render_with_layout(:staff)
end

# Form - Edit a specific staff member
get '/admin/staff/:staff_id/edit/?' do
  staff_id = params[:staff_id].to_i 
  @staff_profile = @storage.load_staff_profile(staff_id)
  @disciplines = @storage.load_disciplines

  render_with_layout(:edit_staff)
end

# Edit a specific staff member
post '/admin/staff/:staff_id/edit' do
  staff_id = params[:staff_id]
  redirect_if_missing_id('staff', staff_id, '/admin/staff/')
  
  first_name, last_name = params[:first_name], params[:last_name]
  session[:errors].push(*edit_staff_errors(first_name, last_name))
  
  if session[:errors].any?
    @staff_profile = @storage.load_staff_profile(staff_id)
    @disciplines = @storage.load_disciplines

    render_with_layout(:edit_staff)
  else
    email, phone, biography = params[:email], params[:phone], params[:biography]
    discipline_ids = params[:discipline_ids].to_a

    @storage.update_staff_profile(staff_id, first_name, last_name, 
                                  email: email, phone: phone, biography: biography,
                                  discipline_ids: discipline_ids)
    
    redirect "/admin/staff/#{staff_id}/"
  end
end

# Delete a specific staff member
post '/admin/staff/:staff_id/delete' do
  staff_id = params[:staff_id]
  redirect_if_missing_id('staff', staff_id, '/admin/staff')

  deleted = @storage.delete_staff_member(staff_id).first
  # Validate from DB (appts)
  name = "#{deleted['first_name']} #{deleted['last_name']}"
  session[:success] = "Staff member #{name} successfully deleted."

  redirect '/admin/staff'
end

# # Admin - Patients # #
# View all patients
get '/admin/patients/?' do
  @patients = @storage.load_all_patients

  render_with_layout(:all_patients)
end

# - Form: Create a new patient
get '/admin/patients/new/?' do
  render_with_layout(:new_patient)
end

# - Create a new patient
post '/admin/patients/new' do
  first_name, last_name = params[:first_name], params[:last_name]
  session[:errors].push(*new_staff_errors(first_name, last_name))
  
  if session[:errors].any?
    render_with_layout(:new_patient)
  else
    email, phone = params[:email], params[:phone] 
    birthday = normalize_date_input(params[:birthday])

    patient_id = @storage.create_patient_return_user_id(
                  first_name, last_name, email: email, 
                  phone: phone, birthday: birthday)

    redirect "/admin/patients/#{patient_id}"
  end
end

# - View a specific patient profile
get '/admin/patients/:patient_id/?' do
  patient_id = params[:patient_id]
  redirect_if_missing_id('patients', patient_id, '/admin/patients')

  @patient = @storage.load_patient(patient_id)
  stats = @storage.load_patient_stats(patient_id)

  @profile = PatientProfile.new(@patient, total_appts: stats[:total_appts]) 

  render_with_layout(:patient)
end

# - Form: Edit a patient
get '/admin/patients/:patient_id/edit/?' do
  patient_id = params[:patient_id]
  redirect_if_missing_id('patients', patient_id, '/admin/patients')

  @patient = @storage.load_patient(patient_id)
  render_with_layout(:edit_patient)
end

# - Edit a patient
post '/admin/patients/:patient_id/edit' do
  patient_id = params[:patient_id]
  redirect_if_missing_id('patients', patient_id, '/admin/patients')

  first_name, last_name = params[:first_name], params[:last_name]
  session[:errors].push(*edit_patient_errors(first_name, last_name))
  if session[:errors].any?
    @patient = @storage.load_patient(patient_id)

    render_with_layout(:edit_patient)
  else
    email, phone = params[:email], params[:phone] 
    birthday = normalize_date_input(params[:birthday])

    @storage.update_patient(patient_id, first_name, last_name,
                            email: email, phone: phone, birthday: birthday)
    
    redirect "/admin/patients/#{patient_id}"
  end
end

# - Delete a patient
post '/admin/patients/:patient_id/delete' do
  patient_id = params[:patient_id]
  redirect_if_missing_id('patients', patient_id, '/admin/patients')

  deleted = @storage.delete_patient(patient_id).first
  # Validate from DB (appts)
  name = "#{deleted['first_name']} #{deleted['last_name']}"
  session[:success] = "Patient #{name} successfully deleted."

  redirect '/admin/patients'
end

# # Admin - Settings # # 
# - Settings Dashboard
get '/admin/settings/?' do
  render_with_layout(:settings)
end

# # Settings - Disciplines # #
# - View all disciplines
get '/admin/disciplines/?' do
  @disciplines = @storage.load_disciplines
  @counts = @storage.count_practitioners_by_disciplines
  
  render_with_layout(:disciplines)
end

# Form - Create a new discipline
get '/admin/disciplines/new/?' do
  render_with_layout(:new_discipline)
end

# - Create a new discipline
post '/admin/disciplines/new' do
  name, title = params[:name], params[:title]

  session[:errors].push(*new_discipline_errors(name, title))
  
  if session[:errors].any?
    render_with_layout(:new_discipline)
  else
    @storage.create_discipline(name, title)
    
    redirect '/admin/disciplines'
  end
end

# Form - Edit a specific discipline
get '/admin/disciplines/:discipline_id/edit/?' do
  discipline_id = params[:discipline_id]
  redirect_if_missing_id('disciplines', discipline_id, '/admin/disciplines')

  @discipline = @storage.load_discipline(discipline_id)
  
  render_with_layout(:edit_discipline)
end

# Edit a specific discipline
post '/admin/disciplines/:discipline_id/edit' do
  discipline_id = params[:discipline_id]
  redirect_if_missing_id('disciplines', discipline_id, '/admin/disciplines')

  name, title = params[:name], params[:title]
  session[:errors].push(*edit_discipline_errors(name, title, discipline_id))

  if session[:errors].any?
    @discipline = @storage.load_discipline(discipline_id)

    render_with_layout(:edit_discipline)
  else
    @storage.update_discipline(discipline_id, name, title)
    session[:success] = 'Discipline successfully updated.'

    redirect "/admin/disciplines"
  end
end

# # Settings - Treatments # # 
# - View all treatments, ordered by discipline
get '/admin/treatments/?' do
  @disciplines = @storage.load_disciplines
  @treatments_by_discipline = group_treatments_by_discipline(@storage.load_treatments)

  render_with_layout(:treatments)
end

# Form - Create a new treatment
get '/admin/treatments/new/?' do
  @disciplines = @storage.load_disciplines
  @tx_lengths = Treatment.lengths

  render_with_layout(:new_treatment)
end

# - Create a new treatment
post '/admin/treatments/new/?' do
  discipline_id = params[:discipline_id].to_i
  name = params[:name]
  length, price = params[:length], params[:price]

  session[:errors].push(*new_treatment_errors(discipline_id, name, length, price))

  if session[:errors].any? 
    @disciplines = @storage.load_disciplines
    @tx_lengths = Treatment.lengths

    render_with_layout(:new_treatment)
  else
    @storage.create_treatment(name, discipline_id, length, price)
    session[:success] = 'Successfully created treatment.'
    
    redirect '/admin/treatments'
  end
end

# Form - Edit a treatment
get '/admin/treatments/:treatment_id/edit/?' do
  treatment_id = params[:treatment_id]
  redirect_if_missing_id('treatments', treatment_id, '/admin/treatments')

  @treatment = @storage.load_treatment(treatment_id)
  @disciplines = @storage.load_disciplines
  @tx_lengths = Treatment.lengths
  
  render_with_layout(:edit_treatment)
end

# - Edit a treatment
post '/admin/treatments/:treatment_id/edit' do
  treatment_id = params[:treatment_id]
  redirect_if_missing_id('treatments', treatment_id, '/admin/treatments')

  discipline_id = params[:discipline_id]
  name, length, price = params.values_at(:name, :length, :price)

  session[:errors].push(*edit_treatment_errors(discipline_id, name, length, price))

  if session[:errors].any?
    @treatment = @storage.load_treatment(treatment_id)
    @disciplines = @storage.load_disciplines
    @tx_lengths = Treatment.lengths
    
    render_with_layout(:edit_treatment)
  else
    @storage.update_treatment(treatment_id, name, discipline_id, length, price)
    session[:success] = 'Treatment successfully updated.'
    redirect '/admin/treatments'
  end
end


# Helpers #
def redirect_if_missing_id(type, id, path)
  unless @storage.record_exists?(type, id)
    session[:errors] << "Hmm..that #{type.singularize} (id = #{id}) could not be found."
    redirect path
  end
end

# Formatting # 
def normalize_date_input(date_string)
  date_string.to_s.strip.empty? ? nil : date_string
end

def group_treatments_by_discipline(treatments)
  treatments.group_by { |tx| tx.discipline.id }
end

# Error Message Setting #
# - Errors for inserting a new staff member
def new_staff_errors(first_name, last_name)
  user_name_errors(first_name, last_name)
end
# - Errors for updating an existing staff member 
def edit_staff_errors(first_name, last_name)
  user_name_errors(first_name, last_name)
end
# - Errors for creating a new patient
def new_patient_errors(first_name, last_name)
  user_name_errors(first_name, last_name)
end
# - Errors for updating an existing patient
def edit_patient_errors(first_name, last_name)
  user_name_errors(first_name, last_name)
end
# - Errors for user (Patient/Staff) names
def user_name_errors(first_name, last_name)
  errors = []
  errors.push(empty_field_error(:first_name, first_name),
              empty_field_error(:last_name, last_name))
  errors
end

# - Errors for creating a new discipline
def new_discipline_errors(name, title)
  discipline_errors(name, title)
end

# - Errors for editing an existing discipline
def edit_discipline_errors(name, title, id)
  discipline_errors(name, title, id: id)
end

# - Errors for creating/editing disciplines
def discipline_errors(name, title, id: nil)
  errors = []
  errors.push(empty_field_error(:name, name), empty_field_error(:title, title),
    name_collision_error(table_name: 'disciplines', column_name: 'name', 
      column_value: name, id: id))

  errors
end 

# - Errors for creating new treatments
def new_treatment_errors(discipline_id, name, length, price)
  treatment_errors(discipline_id, name, length, price)
end

# - Errors for editing existing treatments
def edit_treatment_errors(discipline_id, name, length, price)
  treatment_errors(discipline_id, name, length, price)
end

# - Errors for creating/editing treatments
def treatment_errors(discipline_id, name, length, price)
  errors = []
  errors.push(empty_field_error(:name,  name), empty_field_error(:price, price))
  errors.push(negative_price_error(price))
  errors.push(invalid_select_error('length', length, Treatment.lengths))
  errors.push(invalid_treatment_discipline_id_error(discipline_id))

  errors
end

# - Error if a given price value is negative.
def negative_price_error(price)
  'Please enter a non-negative price.' if price.to_f.negative?
end

# - Error if a treatment's discipline ID does not exist
def invalid_treatment_discipline_id_error(discipline_id)
  unless @storage.record_exists?('disciplines', discipline_id)
    "Discipline ID (#{discipline_id}) does not match any existing disciplines."
  end
end


  
# Validations #
def name_collision_error(table_name:, column_name:, column_value: , id:)
  if @storage.record_collision?(table_name: table_name, column_name: column_name,
                       column_value: column_value, id: id)
    "Another #{table_name.singularize} named #{column_value} already exists."
  end
end

def empty_field_error(attr_name, attr_value)
  attr_name = attr_name.to_s.gsub('_', ' ')

  "Please enter a #{attr_name}." if empty_string?(attr_value)
end

def invalid_select_error(attr_name, option_value, options)
  option_value = option_value.to_s
  options = options.map(&:to_s)

  "Please select a valid #{attr_name}." unless options.include?(option_value)
end

def empty_string?(string)
  string.to_s.strip.empty?
end