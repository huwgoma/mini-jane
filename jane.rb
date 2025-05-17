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

  def was_checked?(group, value)
    return if params[group].nil?

    params[group].include?(value.to_s)
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

######### 
# To Do #
#########
# - CRUD for staff
# - Revisit nils (specifically - how optional fields are represented in schema)
# 
# - CRUD for patients
# - CRUD for appointments
# - CRUD for disciplines
# - CRUD for treatments
# - Flesh out schedule 


# # # # # # # # # # 
# Admin - Schedule # 
# # # # # # # # # # 

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

# # # # # # # # # 
# Admin - Staff # 
# # # # # # # # # 

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

    @storage.create_staff_profile(user_id, params[:biography])
    @storage.add_staff_disciplines(user_id, params[:discipline_ids])
    binding.pry
    # Create user
    # Create staff
    # Create staff disciplines for each discipline; if none, admin
  end

end

# View all staff
get '/admin/staff/?' do
  @staff = @storage.load_all_staff

  render_with_layout(:all_staff)
end

# View a specific staff member
get '/admin/staff/:staff_id/?' do
  staff_id = params[:staff_id].to_i
  @staff_member = @storage.load_staff_member(staff_id)

  render_with_layout(:staff)
end

# # # # # #  
# Helpers #
# # # # # #

# # # # # # # # #  
# Error Messages #
def new_staff_errors(first_name, last_name)
  errors = []
  errors << 'Please enter a first name.' if empty_string?(first_name)
  errors << 'Please enter a last name.' if empty_string?(last_name)
  errors
end

# # # # # # # #   
# Validations #
def empty_string?(string)
  string.strip.empty?
end