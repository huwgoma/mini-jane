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

  # Practitioners (Clinical Staff Members)

  def load_daily_appointments(date)
    sql = <<~SQL
      SELECT su.id AS staff_id,
             CONCAT(su.first_name, ' ', su.last_name) AS staff_name,
             pu.id AS patient_id, 
             CONCAT(pu.first_name, ' ', pu.last_name) AS patient_name,
             treatments.name AS tx_name,
             treatments.duration AS tx_duration,
             appts.date_time::time AS appt_time
      FROM appointments AS appts
        JOIN staff       ON appts.staff_id = staff.user_id
        JOIN users AS su ON staff.user_id = su.id
        JOIN patients    ON appts.patient_id = patients.user_id
        JOIN users AS pu ON patients.user_id = pu.id
        JOIN treatments ON appts.treatment_id = treatments.id
      WHERE appts.date_time::date = $1;
    SQL
    result = query(sql, date)

  end

  private

  attr_reader :connection, :logger

  # Formatting Methods (PG::Result -> Application Format)
  def format_practitioner
    
  end
end