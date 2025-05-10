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
end