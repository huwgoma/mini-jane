require 'pg'

class PGAdapter
  def initialize
    @connection = PG.connect(dbname: 'jane')
  end
  
  def query(sql, *params)
    @connection.exec_params(sql, params)
  end

  def load_daily_schedule(date)
    practitioners = load_scheduled_practitioners
    
    appointments = load_scheduled_appointments(date)
    binding.pry
    
    # Format into application structure
  end

  #private

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
      GROUP BY users.id;  
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
      WHERE appts.date_time::date = $1;
    SQL

    query(sql, date)
  end
end