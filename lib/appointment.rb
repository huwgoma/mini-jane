class Appointment
  attr_reader :id, :pt_name, :tx_name, :datetime
  
  def initialize(id, datetime, patient:, staff_name:, treatment:)
    @id = id
    @datetime = datetime
    @patient = patient
    @staff_name = staff_name
    @treatment = treatment
  end

  def self.from_partial_data(id, datetime, patient: nil, 
                             staff_name: nil, treatment: nil)
    self.new(id, datetime, patient: patient, 
             staff_name: staff_name, treatment: treatment)
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