class User
  attr_reader :id, :first_name, :last_name, :email, :phone, :birthday

  def initialize(id, first_name, last_name, 
                 email: nil, phone: nil, birthday: nil)
    @id = id
    @first_name, @last_name = first_name, last_name
    @email, @phone = email, phone
    @birthday = @birthday
  end

  def full_name
    "#{first_name} #{last_name}" 
  end
end

class Patient < User
  
end

class Staff < User
  attr_reader :disciplines 

  def initialize(id, first_name, last_name, 
                 email: nil, phone: nil, bio: nil, disciplines: nil)
    super(id, first_name, last_name, email: email, phone: phone)
    
    @bio = bio
    @disciplines = disciplines
  end

  def bio
    @bio.to_s.strip
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