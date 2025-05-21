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

  def record_exists?(table_name, id)
    table_whitelist = schema_table_names
    return unless table_whitelist.include?(table_name)

    pk_column_name = schema_primary_key_column_name(table_name)
    sql = "SELECT * FROM #{table_name} 
           WHERE #{pk_column_name} = $1;"

    query(sql, id).ntuples.positive?
  end

  # Schedule # 
  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    appointments = load_scheduled_appointments(date)

    format_daily_schedule(practitioners, appointments)
  end

  # Users #
  def create_user_return_id(first_name, last_name, email, phone)
    sql = "INSERT INTO users(first_name, last_name, email, phone)
           VALUES($1, $2, $3, $4) RETURNING id;"
    result = query(sql, first_name, last_name, email, phone)

    result.first['id'].to_i
  end

  # Staff #
  # - Member: Refers to the actual staff table
  # - Profile: Refers to a staff member + related users/disciplines
  def create_staff_member(user_id, biography)
    sql = "INSERT INTO staff(user_id, biography)
           VALUES($1, $2);"
    query(sql, user_id, biography)
  end

  def load_all_staff
    sql = "SELECT users.id, users.first_name, users.last_name 
           FROM users JOIN staff ON users.id = staff.user_id
           ORDER BY first_name, last_name, user_id;"
    result = query(sql)

    result.map { |staff| format_user_listing(staff, staff: true) }
  end

  def load_staff_profile(staff_id)
    staff = load_staff_member(staff_id).first
    return if staff.nil?
    
    staff_disciplines_result = load_disciplines_by_staff(staff_id)
    
    format_staff_profile(staff, staff_disciplines_result)
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

  def update_staff_profile(staff_id, first_name, last_name, 
                           email: nil, phone: nil, biography: nil, 
                           discipline_ids: [])
    update_user(staff_id, first_name, last_name, email, phone)
    update_staff_member(staff_id, biography)
    overwrite_staff_disciplines(staff_id, discipline_ids)
  end

  def delete_staff_member(staff_id)
    # Cascades to staff -> staff_disciplines & appointments
    sql = "DELETE FROM users WHERE id = $1 RETURNING *;"
    query(sql, staff_id)
  end

  def overwrite_staff_disciplines(staff_id, discipline_ids)
    delete_sql = "DELETE FROM staff_disciplines WHERE staff_id = $1;"
    query(delete_sql, staff_id)

    add_staff_disciplines(staff_id, discipline_ids)
  end
  
  # Patients # 
  

  # Disciplines #
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

  # Query the names of all tables in public schema
  def schema_table_names
    sql = "SELECT table_name FROM information_schema.tables
           WHERE table_schema = 'public';"
    result = query(sql)

    result.map { |row| row['table_name'] }
  end

  # Query the name of the PRIMARY KEY column 
  def schema_primary_key_column_name(table_name)
    sql = <<~SQL
      SELECT DISTINCT ccu.column_name
      FROM  information_schema.constraint_column_usage ccu
      JOIN  information_schema.table_constraints       tc
      ON    ccu.table_schema = tc.table_schema AND ccu.table_name = tc.table_name
      WHERE ccu.table_schema   = 'public' AND
            ccu.table_name     = $1       AND
            tc.constraint_type = 'PRIMARY KEY';
    SQL
    result = query(sql, table_name)

    result.first['column_name']
  end

  # # # # # # # # # # # 
  # Private DB Methods #
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

  # Users 
  def update_user(id, first_name, last_name, email, phone)
    sql = <<~SQL
      UPDATE users
      SET first_name = $2, last_name = $3,
          email = $4, phone = $5
      WHERE id = $1;
    SQL

    query(sql, id, first_name, last_name, email, phone)
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

  def update_staff_member(user_id, biography)
    sql = <<~SQL
      UPDATE staff
      SET biography = $2
      WHERE user_id = $1;
    SQL

    query(sql, user_id, biography)
  end

  # Formatting Methods (PG::Result -> Application Format) #
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

  def format_user_listing(user, staff: false)
    id = user['id'].to_i
    first_name, last_name = user['first_name'], user['last_name']
    type = staff ? Staff : Patient
    
    type.new(id, first_name, last_name)
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