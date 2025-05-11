class User
  attr_reader :first_name, :last_name

  def initialize(id, first_name, last_name)
    @id = id
    @first_name, @last_name = first_name, last_name
  end

  def full_name
    "#{first_name} #{last_name}" 
  end
end

class Patient < User
  
end

class Staff < User
  
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