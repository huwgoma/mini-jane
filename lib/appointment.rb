class Appointment
  attr_reader :pt_name, :tx_name, :datetime
  
  def initialize(id, pt_name, tx_name, tx_length, datetime)
    @id = id
    @pt_name = pt_name
    @tx_name, @tx_length = tx_name, tx_length
    @datetime = datetime
  end

  def time
    datetime.strftime('%H:%M%p')    
  end

  def to_s
    "#{time} - #{pt_name} - #{tx_name}"
  end
end