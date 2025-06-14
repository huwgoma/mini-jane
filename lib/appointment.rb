class Appointment
  attr_reader :id, :patient, :practitioner, :treatment, :datetime
  
  def initialize(id, datetime, patient:, practitioner:, treatment:)
    @id = id
    @datetime = datetime
    @patient = patient
    @practitioner = practitioner
    @treatment = treatment
  end

  def self.from_partial_data(id: nil, datetime: nil, patient: nil, 
    practitioner: nil, treatment: nil)
    
    self.new(id, datetime, patient: patient, 
      practitioner: practitioner, treatment: treatment)
  end

  def end_time
    datetime.to_time + (treatment.length.to_i * 60)
  end

  def start_time
    datetime.to_time
  end

  def date
    datetime.to_date
  end
end