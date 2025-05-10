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


    # Format into application structure
  end

  def load_scheduled_practitioners
    sql = <<~SQL
      SELECT users.id AS staff_id, users.first_name,
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
end