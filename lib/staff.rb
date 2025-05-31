require_relative 'user'

class StaffRepository
  # def self.clinical?(id, storage)
  #   sql = "SELECT 1 FROM staff_disciplines WHERE staff_id = $1;"
  #   storage.query(sql, id).ntuples.positive?
  # end

  def self.offers_treatment?(staff_id, treatment_id, storage)
    sql = "SELECT 1 FROM treatments
           JOIN disciplines ON treatments.discipline_id = disciplines.id
           JOIN staff_disciplines sd ON disciplines.id = sd.discipline_id
           WHERE sd.staff_id = $1 AND treatments.id = $2;"
    storage.query(sql, staff_id, treatment_id).ntuples.positive?
  end
end

class Staff < User
  attr_reader :disciplines 

  def initialize(id, first_name, last_name, email: nil, phone: nil, 
                 biography: nil, disciplines: [])
    super(id, first_name, last_name, email: email, phone: phone)
    
    @biography = biography
    @disciplines = disciplines # ADmin if empty
  end

  def self.from_partial_data(id: nil, first_name: nil, last_name: nil,
    email: nil, phone: nil, biography: nil, disciplines: [])
    
    self.new(id, first_name, last_name, 
      email: email, phone: phone, biography: biography, disciplines: disciplines)
  end

  def biography
    @biography.to_s.strip
  end

  # def clinical?(storage)
  #   StaffRepository.clinical?(@id, storage)
  # end

  def offers_treatment?(treatment_id, storage)
    StaffRepository.offers_treatment?(@id, treatment_id, storage)
  end
end

class Practitioner < Staff
  attr_reader :schedule

  def initialize(id, first_name, last_name, appointments = [])
    super(id, first_name, last_name)
    @schedule = []
    add_to_schedule(appointments)
  end

  def add_to_schedule(*appointments)
    # Validate 
    schedule.push(*appointments.flatten)
  end
end