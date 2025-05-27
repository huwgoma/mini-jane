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

    return false if id.to_s.strip.empty?

    pk_column_name = schema_primary_key_column_name(table_name)

    sql = "SELECT 1 FROM #{table_name} 
           WHERE #{pk_column_name} = $1"

    query(sql, id).ntuples.positive?
  end

  def record_collision?(table_name:, column_name:, column_value:, id: nil)
    table_whitelist = schema_table_names
    return unless table_whitelist.include?(table_name)

    column_whitelist = schema_column_names(table_name)
    return unless column_whitelist.include?(column_name)

    sql = "SELECT 1 FROM #{table_name} 
           WHERE #{column_name} = $2
           AND ($1::integer IS NULL OR id <> $1);"

    query(sql, id, column_value).ntuples.positive?
  end

  # Schedule # 
  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    appointments = load_scheduled_appointments(date)

    format_daily_schedule(practitioners, appointments)
  end

  # Appointments #
  def load_appointment_info(id)
    sql = <<~SQL
      SELECT appointments.id, patients.user_id AS pt_id,
             pu.first_name AS pt_first_name, pu.last_name AS pt_last_name,
             su.first_name AS staff_first_name, su.last_name AS staff_last_name,
             treatments.id AS tx_id, treatments.name AS tx_name, 
             treatments.length AS tx_length, treatments.price AS tx_price, 
             appointments.datetime
      FROM appointments 
      JOIN staff      ON appointments.staff_id = staff.user_id
      JOIN users su   ON staff.user_id = su.id
      JOIN patients   ON appointments.patient_id = patients.user_id
      JOIN users pu   ON patients.user_id = pu.id
      JOIN treatments ON appointments.treatment_id = treatments.id
      WHERE appointments.id = $1
    SQL

    result = query(sql, id)

    format_appointment(result.first)
  end

  # Users #
  
  # Staff #
  # - Member: Refers to the actual staff table
  # - Profile: Refers to a staff member + related users/disciplines
  def create_staff_return_user_id(first_name, last_name, user_id: nil,
                                  email: nil, phone: nil, biography: nil)
    user_id ||= create_user_return_id(
                  first_name, last_name, email: email, phone: phone)
    staff_sql = "INSERT INTO staff(user_id, biography)
                 VALUES($1, $2) RETURNING user_id;"
    result = query(staff_sql, user_id, biography)

    result.first['user_id'].to_i
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
    update_user(staff_id, first_name, last_name, email: email, phone: phone)
    update_staff_member(staff_id, biography: biography)
    overwrite_staff_disciplines(staff_id, discipline_ids)
  end

  def delete_staff_member(staff_id)
    # Do not allow deletion if staff has any appointments.
    delete_user(staff_id)
  end

  def overwrite_staff_disciplines(staff_id, discipline_ids)
    delete_sql = "DELETE FROM staff_disciplines WHERE staff_id = $1;"
    query(delete_sql, staff_id)

    add_staff_disciplines(staff_id, discipline_ids)
  end
  
  # Patients # 
  # - Patient: The 'core' patient info (Name, Birthday, Email, etc.)
  # - Patient Stats: Auxiliary patient info (Appointment/Billing Stats)
  def load_all_patients
    sql = "SELECT users.id, users.first_name, users.last_name 
           FROM users JOIN patients ON users.id = patients.user_id
           ORDER BY users.last_name, users.first_name;"
    result = query(sql)

    result.map { |patient| format_user_listing(patient) }
  end

  def load_patient(patient_id)
    sql = "SELECT users.id, users.first_name, users.last_name,
           users.email, users.phone, patients.birthday,
           REPLACE(AGE(current_date, patients.birthday)::text, 'mons', 'months') AS age
           FROM users JOIN patients ON users.id = patients.user_id
           WHERE patients.user_id = $1;"
    result = query(sql, patient_id)

    format_patient(result.first)
  end

  # Total Appts, Upcoming Appts, No Shows, Time since Last Visit,
  # Claims Outstanding, Private Outstanding, Credit, etc.
  def load_patient_stats(patient_id)
    sql = "SELECT COUNT(appointments.id) AS total_appts
           FROM patients
           JOIN appointments ON patients.user_id = appointments.patient_id
           WHERE patients.user_id = $1;"
    result = query(sql, patient_id)

    format_patient_stats(result.first)
  end

  def create_patient_return_user_id(first_name, last_name, user_id: nil, 
                                    email: nil, phone: nil, birthday: nil)
    user_id ||= create_user_return_id(
                  first_name, last_name, email: email, phone: phone)
    patient_sql = "INSERT INTO patients (user_id, birthday)
                   VALUES($1, $2) RETURNING user_id;"
                   
    result = query(patient_sql, user_id, birthday)

    result.first['user_id'].to_i
  end

  def update_patient(id, first_name, last_name, 
                     email: nil, phone: nil, birthday: nil)
    update_user(id, first_name, last_name, email: email, phone: phone)
    
    sql = "UPDATE patients 
           SET birthday = $2
           WHERE user_id = $1;"
    query(sql, id, birthday)
  end

  def delete_patient(patient_id)
    # Do not allow deletion if patient has any appointments.
    delete_user(patient_id)
  end

  # Disciplines #
  def load_disciplines
    sql = "SELECT * FROM disciplines ORDER BY id;"
    result = query(sql)
    result.map { |discipline| format_discipline(discipline) }
  end

  def load_discipline(discipline_id)
    sql = "SELECT * FROM disciplines WHERE id = $1;"
    result = query(sql, discipline_id)

    format_discipline(result.first)
  end

  def count_practitioners_by_disciplines
    sql = "SELECT disciplines.id, COUNT(staff_disciplines.staff_id) 
           FROM disciplines 
           LEFT JOIN staff_disciplines ON disciplines.id = discipline_id
           GROUP BY disciplines.id ORDER BY disciplines.id;"
    result = query(sql)

    result.map { |row| [ row['id'].to_i, row['count'].to_i ] }.to_h
  end

  def create_discipline(name, title)
    sql = "INSERT INTO disciplines (name, title)
           VALUES ($1, $2);"

    query(sql, name, title)
  end

  def update_discipline(discipline_id, name, title)
    sql = "UPDATE disciplines
           SET name = $2, title = $3
           WHERE id = $1;"
    query(sql, discipline_id, name, title)
  end

  # Treatments # 
  def load_treatments
    sql = "SELECT * FROM treatments ORDER BY discipline_id, id;"
    result = query(sql)

    result.map { |treatment| format_treatment(treatment) }
  end

  def load_treatment(id)
    sql = "SELECT * FROM treatments WHERE id = $1;"

    format_treatment(query(sql, id).first)
  end

  def create_treatment(name, discipline_id, length, price)
    sql = "INSERT INTO treatments (name, discipline_id, length, price)
           VALUES ($1, $2, $3, $4);"
    query(sql, name, discipline_id, length, price)
  end

  def update_treatment(id, name, discipline_id, length, price)
    sql = "UPDATE treatments 
           SET name = $2, discipline_id = $3,
               length = $4, price = $5
           WHERE id = $1;"
    query(sql, id, name, discipline_id, length, price)
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

  # Query the names of all columns in the specified table
  def schema_column_names(table_name)
    sql = "SELECT column_name FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = $1;"
    result = query(sql, table_name)

    result.map { |row| row['column_name'] }
  end

  # Query the name of the PRIMARY KEY column 
  def schema_primary_key_column_name(table_name)
    sql = <<~SQL
      SELECT DISTINCT ccu.column_name
      FROM  information_schema.constraint_column_usage ccu
      JOIN  information_schema.table_constraints       tc
      ON    ccu.table_schema = tc.table_schema 
        AND ccu.table_name = tc.table_name
        AND ccu.constraint_name = tc.constraint_name
      WHERE ccu.table_schema   = 'public' AND
            ccu.table_name     = $1       AND
            tc.constraint_type = 'PRIMARY KEY';
    SQL
    result = query(sql, table_name)
    result.first['column_name']
  end

  # Private DB Methods # 
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
      SELECT appts.id, appts.datetime, appts.staff_id AS staff_id,
             patients.user_id AS pt_id,
             users.first_name AS pt_first_name, users.last_name AS pt_last_name,
             treatments.id AS tx_id, treatments.name AS tx_name, treatments.length AS tx_length
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
  def create_user_return_id(first_name, last_name, email: nil, phone: nil)
    sql = "INSERT INTO users(first_name, last_name, email, phone)
           VALUES($1, $2, $3, $4) RETURNING id;"
    result = query(sql, first_name, last_name, email, phone)

    result.first['id'].to_i
  end

  def update_user(id, first_name, last_name, email: nil, phone: nil)
    sql = <<~SQL
      UPDATE users
      SET first_name = $2, last_name = $3,
          email = $4, phone = $5
      WHERE id = $1;
    SQL

    query(sql, id, first_name, last_name, email, phone)
  end

  def delete_user(id)
    # Cascades to either Staff or Patients
    sql = "DELETE FROM users WHERE id = $1 RETURNING *;"
    query(sql, id)
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

  def update_staff_member(user_id, biography: nil)
    sql = <<~SQL
      UPDATE staff
      SET biography = $2
      WHERE user_id = $1;
    SQL

    query(sql, user_id, biography)
  end

  # Formatting Methods (PG::Result -> Application Format) #
  def format_daily_schedule(practitioners, appointments)
    appointments_by_staff_id = format_appointment_listings_by_staff_id(appointments)
    schedule = format_practitioners_by_discipline(practitioners, appointments_by_staff_id)
    
    schedule
  end

  def format_appointment_listings_by_staff_id(appointments)
    appointments.each_with_object({}) do |row, hash|
      appt_id = row['id'].to_i
      staff_id = row['staff_id'].to_i


      patient = Patient.from_partial_data(first_name: row['pt_first_name'],
        last_name: row['pt_last_name'])
      treatment = Treatment.from_partial_data(name: row['tx_name'],
        length: row['tx_length'].to_i)
      datetime = DateTime.parse(row['datetime'])

      appointment = Appointment.from_partial_data(id: appt_id, 
        datetime: datetime, patient: patient, treatment: treatment)

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

  def format_appointment(appt)
    appt_id, pt_id = appt.values_at('id', 'pt_id')
    pt_first_name, pt_last_name = appt.values_at('pt_first_name', 'pt_last_name')
    staff_first_name, staff_last_name = appt.values_at('staff_first_name', 'staff_last_name')
    tx_id, tx_name = appt.values_at('tx_id', 'tx_name')
    tx_length, tx_price = appt.values_at('tx_length', 'tx_price')
    
    patient = Patient.from_partial_data(id: pt_id, 
      first_name: pt_first_name, last_name: pt_last_name)
    staff = Staff.from_partial_data(first_name: staff_first_name, last_name: staff_last_name)
    treatment = Treatment.from_partial_data(id: tx_id, name: tx_name,
      length: tx_length, price: tx_price)    
    datetime = DateTime.parse(appt['datetime'])

    Appointment.new(appt_id, datetime, 
      patient: patient, staff: staff, treatment: treatment)
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

  def format_patient(patient)
    id = patient['id'].to_i
    first_name, last_name = patient['first_name'], patient['last_name']
    email, phone = patient['email'], patient['phone']
    birthday, age = patient['birthday'], patient['age']
    
    Patient.new(id, first_name, last_name, email: email, 
                phone: phone, birthday: birthday, age: age)
  end

  def format_patient_stats(stats)
    total_appts = stats['total_appts'].to_i

    { total_appts: total_appts }
  end

  def format_discipline(discipline)
    id = discipline['id'].to_i
    name = discipline['name']
    title = discipline['title']

    Discipline.new(id, name, title)
  end

  def format_treatment(treatment)
    id, discipline_id = treatment['id'].to_i, treatment['discipline_id'].to_i
    name = treatment['name']
    length = treatment['length'].to_i
    price = treatment['price'].sub(/\$/, '').to_f

    Treatment.new(id, name, discipline_id: discipline_id, 
      length: length, price: price)
  end
end