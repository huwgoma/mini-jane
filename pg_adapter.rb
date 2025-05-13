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

  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    appointments = load_scheduled_appointments(date)

    format_daily_schedule(practitioners, appointments)
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

  def load_scheduled_practitioners
    sql = <<~SQL
      SELECT users.id AS staff_id, users.first_name, users.last_name,
             STRING_AGG(disciplines.name, '/') AS disciplines
      FROM users
      JOIN staff ON users.id = staff.user_id
      JOIN staff_disciplines sd ON staff.user_id = sd.staff_id
      JOIN disciplines ON sd.discipline_id = disciplines.id
      WHERE disciplines.clinical = true
      GROUP BY users.id
      ORDER BY STRING_AGG(disciplines.id::text, '');
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

  # Formatting Methods (PG::Result -> Application Format)
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
      datetime = row['datetime']

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
end