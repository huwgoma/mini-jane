class Appointment
  def initialize(id, pt_name, tx_name, tx_length, datetime)
    @id = id
    @pt_name = pt_name
    @tx_name, @tx_length = tx_name, tx_length
    @datetime = datetime
  end
end