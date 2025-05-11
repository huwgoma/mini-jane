require 'pg'

class PGAdapter
  def initialize(logger: nil)
    @logger = logger
    @connection = PG.connect(dbname: 'jane')
  end

  def query(sql, *params)
    logger.info("#{sql}, #{params}")
    connection.exec_params(sql, params)
  end

  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    
    appointments = load_scheduled_appointments(date)
    format_daily_schedule(practitioners, appointments)
    
    # Format into application structure
  end

  private

  attr_reader :connection, :logger
  
  def load_scheduled_practitioners
    sql = <<~SQL
      SELECT users.id AS staff_id, 
             CONCAT(users.first_name, ' ', users.last_name) AS name,
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
             CONCAT(users.first_name, ' ', users.last_name) AS patient_name,
             treatments.name AS tx_name, treatments.duration AS tx_length,
             appts.date_time AS "datetime"
      FROM appointments AS appts
      JOIN patients ON appts.patient_id = patients.user_id
      JOIN users ON patients.user_id = users.id
      JOIN treatments ON appts.treatment_id = treatments.id
      WHERE appts.date_time::date = $1
      ORDER BY "datetime";
    SQL

    query(sql, date)
  end

  def format_daily_schedule(practitioners, appointments)
    schedule = {}

    appts_by_staff_id = appointments.each_with_object({}) do |row, appts|
      id = row['id'].to_i
      staff_id = row['staff_id'].to_i
      patient = row['patient_name']
      tx_name = row['tx_name']
      tx_length = row['tx_length']
      datetime = row['datetime']

      appointment = Appointment.new(id, patient, tx_name, tx_length, datetime)

      appts[staff_id] ||= []

      appts[staff_id] << appointment
    end

    practitioners.each do |row|
      id = row['staff_id'].to_i
      disciplines = row['disciplines']
      practitioner = Practitioner.new(id, row['name'])
      appts = appts_by_staff_id[id]
      practitioner.add_appointments(appts)

      schedule[disciplines] ||= {}

      schedule[disciplines][id] = practitioner
    end

    schedule
  end
end