require 'pg'

class PGAdapter
  def initialize
    @connection = PG.connect(dbname: 'jane')
  end
  
  def query(sql, *params)
    @connection.exec_params(sql, params)
  end

  def load_daily_schedule(date)
    practitioners = load_practitioners
    # 1) Load a list of all practitioners 
    # (* scheduled for given date but we do that later)
    # 
    # 2) Load a list of all appointments scheduled for the
    #    given date.
    #  
  end
end