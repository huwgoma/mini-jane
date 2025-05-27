class Appointment
  attr_reader :id, :pt_name, :tx_name, :datetime
  
  def initialize(id, datetime, patient:, staff:, treatment:)
    @id = id
    @datetime = datetime
    @patient = patient
    @staff = staff
    @treatment = treatment    
    

    # @id = id
    # @pt_name = pt_name
    # @tx_name, @tx_length = tx_name, tx_length
    # @datetime = datetime
  end

  def time
    datetime.strftime('%l:%M%p')    
  end

  def date
    datetime.strftime('%A %B %-d, %Y')
  end

  def to_s
    "#{time} - #{pt_name} - #{tx_name}"
  end
end