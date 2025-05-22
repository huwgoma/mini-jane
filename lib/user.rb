class User
  attr_reader :id, :first_name, :last_name, :email, :phone

  def initialize(id, first_name, last_name, 
                 email: nil, phone: nil)
    @id = id
    @first_name, @last_name = first_name, last_name
    @email, @phone = email, phone
  end

  def full_name
    "#{first_name} #{last_name}" 
  end
end

class Patient < User
  attr_reader :birthday, :age, :total_appts
  
  def initialize(id, first_name, last_name, 
                 email: nil, phone: nil, birthday: nil, age: nil,
                 total_appts: 0)
    super(id, first_name, last_name, email: email, phone: phone)

    @birthday, @age = birthday, age
    @total_appts = total_appts
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

  def biography
    @biography.to_s.strip
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