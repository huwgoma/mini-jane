require 'pg'

class PGAdapter
  def initialize(logger: nil)
    @logger = logger
    @connection = nil # Defer connection until needed
  end

  def query(sql, *params)
    logger.info("#{sql}, #{params}") if logger
    
    connection.exec_params(sql, params)
  end

  # # # # # # 
  # Schedule # 
  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    appointments = load_scheduled_appointments(date)

    format_daily_schedule(practitioners, appointments)
  end

  # # # # # 
  # Users #
  def create_user_return_id(first_name, last_name, email, phone)
    sql = "INSERT INTO users(first_name, last_name, email, phone)
           VALUES($1, $2, $3, $4) RETURNING id;"
    result = query(sql, first_name, last_name, email, phone)

    result.first['id'].to_i
  end

  # # # # #
  # Staff #
  def create_staff_profile(user_id, biography)
    sql = "INSERT INTO staff(user_id, biography)
           VALUES($1, $2);"
    query(sql, user_id, biography)
  end

  def load_all_staff
    sql = "SELECT staff.user_id, users.first_name, users.last_name 
           FROM users JOIN staff ON users.id = staff.user_id
           ORDER BY first_name, last_name, user_id;"
    result = query(sql)

    result.map { |staff| format_staff_listing(staff) }
  end

  def load_staff_profile(staff_id)
    staff_result = load_staff_member(staff_id)
    staff_disciplines_result = load_disciplines_by_staff(staff_id)
    
    format_staff_profile(staff_result.first, staff_disciplines_result)
  end

  def add_staff_disciplines(staff_id, discipline_ids)
    # Don't insert if no disciplines are given
    return if discipline_ids.to_a.empty?
    
    placeholders = discipline_ids.map.with_index do |id, index|
      "($1, $#{index + 2})"
    end.join(', ')
    
    sql = "INSERT INTO staff_disciplines (staff_id, discipline_id)
           VALUES #{placeholders};"
    
    query(sql, staff_id, *discipline_ids)
  end

  # Disciplines 
  def load_disciplines
    sql = "SELECT id, name FROM disciplines;"
    result = query(sql)
    result.map { |discipline| format_discipline(discipline) }
  end

  private

  attr_reader :logger

  def connection
    @connection ||= PG.connect(dbname: env_db_name)
  end

  def env_db_name
    case ENV['RACK_ENV']
    when 'test'        then 'test_jane'
    when 'development' then 'jane'
    end
  end

  # # # # # # # # # # # # # #
  # Private Loading Methods #
  # 
  # Schedule # 
  def load_scheduled_practitioners
    sql = <<~SQL
      SELECT users.id AS staff_id, users.first_name, users.last_name,
             STRING_AGG(disciplines.name, '/') AS disciplines
      FROM users
      JOIN staff ON users.id = staff.user_id
      JOIN staff_disciplines sd ON staff.user_id = sd.staff_id
      JOIN disciplines ON sd.discipline_id = disciplines.id
      GROUP BY users.id
      ORDER BY STRING_AGG(disciplines.id::text, ''), users.first_name, users.last_name;
    SQL

    query(sql)
  end

  def load_scheduled_appointments(date)
    sql = <<~SQL
      SELECT appts.id, appts.staff_id, 
             CONCAT(users.first_name, ' ', users.last_name) AS pt_name,
             treatments.name AS tx_name, treatments.length AS tx_length,
             appts.datetime
      FROM appointments AS appts
      JOIN patients ON appts.patient_id = patients.user_id
      JOIN users ON patients.user_id = users.id
      JOIN treatments ON appts.treatment_id = treatments.id
      WHERE appts.datetime::date = $1
      ORDER BY appts.datetime;
    SQL
    query(sql, date)
  end

  # Staff Profile
  def load_staff_member(staff_id)
    sql = "SELECT users.id, users.first_name, users.last_name, 
                  users.email, users.phone, staff.biography
           FROM users
           JOIN staff ON users.id = staff.user_id
           WHERE users.id = $1
           GROUP BY users.id, staff.user_id;"
    query(sql, staff_id)
  end

  def load_disciplines_by_staff(staff_id)
    sql = "SELECT disciplines.id, disciplines.name
           FROM disciplines
           JOIN staff_disciplines ON disciplines.id = discipline_id
           WHERE staff_id = $1;"
    query(sql, staff_id)
  end

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
  # Formatting Methods (PG::Result -> Application Format) #
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  def format_daily_schedule(practitioners, appointments)
    appointments_by_staff_id = format_appointments_by_staff_id(appointments)
    schedule = format_practitioners_by_discipline(practitioners, appointments_by_staff_id)
    
    schedule
  end

  def format_appointments_by_staff_id(appointments)
    appointments.each_with_object({}) do |row, hash|
      id = row['id'].to_i
      staff_id = row['staff_id'].to_i
      pt_name = row['pt_name']
      tx_name = row['tx_name']
      tx_length = row['tx_length'].to_i
      datetime = DateTime.parse(row['datetime'])

      appointment = Appointment.new(id, pt_name, tx_name, tx_length, datetime)

      hash[staff_id] ||= []
      hash[staff_id] << appointment
    end
  end

  def format_practitioners_by_discipline(practitioners, appointments_by_staff_id)
    practitioners.each_with_object({}) do |row, hash|
      staff_id = row['staff_id'].to_i
      disciplines = row['disciplines']
      first_name, last_name = row['first_name'], row['last_name']

      appointments = appointments_by_staff_id.fetch(staff_id, [])
      practitioner = Practitioner.new(staff_id, first_name, last_name, appointments)

      hash[disciplines] ||= {}
      hash[disciplines][staff_id] = practitioner
    end
  end

  def format_user(user)
    id = user['id'].to_i
    first_name, last_name = user['first_name'], user['last_name']
    email, phone = user['email'], user['phone']

    User.new(id, first_name, last_name, email: email, phone: phone)
  end

  def format_staff_listing(staff)
    id = staff['user_id'].to_i
    first_name, last_name = staff['first_name'], staff['last_name']
  
    Staff.new(id, first_name, last_name)
  end

  def format_staff_profile(staff, disciplines)
    id = staff['id'].to_i
    first_name, last_name = staff['first_name'], staff['last_name']
    email, phone = staff['email'], staff['phone']
    biography = staff['biography']

    disciplines = disciplines.map { |discipline| format_discipline(discipline) }
    
    Staff.new(id, first_name, last_name, email: email, phone: phone,
              biography: biography, disciplines: disciplines)
  end

  def format_discipline(discipline)
    id = discipline['id'].to_i
    name = discipline['name']

    Discipline.new(id, name)
  end
end