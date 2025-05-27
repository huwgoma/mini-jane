class Appointment
  attr_reader :id, :patient, :treatment, :datetime
  
  def initialize(id, datetime, patient:, staff:, treatment:)
    @id = id
    @datetime = datetime
    @patient = patient
    @staff = staff
    @treatment = treatment
  end

  def self.from_partial_data(id: nil, datetime: nil, patient: nil, 
    staff: nil, treatment: nil)
    
    self.new(id, datetime, patient: patient, 
      staff: staff, treatment: treatment)
  end

  def time
    datetime.strftime('%l:%M%p')    
  end

  def date
    datetime.strftime('%A %B %-d, %Y')
  end

  def to_s
    "#{time} - #{patient.full_name} - #{treatment.name}"
  end
end