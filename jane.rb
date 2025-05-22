# frozen_string_literal: true

require 'sinatra'
require 'sinatra/contrib'
require 'date_core'
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

# Commit
#
#
######### 
# To Do #
#########
# 1) Refactor #create_staff to use same paradigm as #create_patient
# (create user if user_id is not given); refactor /admin/staff/new 
# accordingly.
# 2) Create helper for extracting params
# 
# - Clear DB ONCE before test suite
# 
# 
# - CRUD for patients
# - CRUD for appointments
# - CRUD for disciplines
# - CRUD for treatments
# - Flesh out schedule 
# - Delete cascade - appointments


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
    user_id = @storage.create_user_return_id(
                params[:first_name], params[:last_name], 
                params[:email], params[:phone])

    @storage.create_staff_member(user_id, params[:biography])
    @storage.add_staff_disciplines(user_id, params[:discipline_ids])

    redirect "/admin/staff/#{user_id}"
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
get '/admin/patients' do
  @patients = @storage.load_all_patients

  render_with_layout(:all_patients)
end

# Form: Create a new patient
get '/admin/patients/new' do
  render_with_layout(:new_patient)
end

# Create a new patient.
post '/admin/patients/new' do
  first_name, last_name = params[:first_name], params[:last_name]
  session[:errors].push(*new_staff_errors(first_name, last_name))
  
  if session[:errors].any?
    render_with_layout(:new_patient)
  else
    email, phone, birthday = params[:email], params[:phone], params[:birthday]
    @storage.create_patient(first_name, last_name, email: email, 
                            phone: phone, birthday: birthday)
    
  end
end

# View a specific patient profile
get '/admin/patients/:patient_id' do
  patient_id = params[:patient_id]
  redirect_if_missing_id('patients', patient_id, '/admin/patients')

  @patient_profile = @storage.load_patient_profile(patient_id)

  render_with_layout(:patient)
end

# private


# Helpers #
def redirect_if_missing_id(type, id, path)
  unless @storage.record_exists?(type, id)
    session[:errors] << "Hmm..that #{type} (id = #{id}) could not be found."
    redirect path
  end
end

# Error Message Setting #
# - Errors for inserting a new staff member
def new_staff_errors(first_name, last_name)
  name_errors(first_name, last_name)
end
# - Errors for updating an existing staff member 
#   (currently identical to new_staff_errors, but may change)
def edit_staff_errors(first_name, last_name)
  name_errors(first_name, last_name)
end
# - Errors for creating a new patient
#   (also currently identical to new_staff_errors)
def new_patient_errors(first_name, last_name)
  name_errors(first_name, last_name)
end

def name_errors(first_name, last_name)
  errors = []
  errors << 'Please enter a first name.' if empty_string?(first_name)
  errors << 'Please enter a last name.' if empty_string?(last_name)
  errors
end
  
# Validations #
def empty_string?(string)
  string.to_s.strip.empty?
end