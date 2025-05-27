require_relative 'user'

class Patient < User
  attr_reader :birthday, :appt_count

  def initialize(id, first_name, last_name, 
                 email: nil, phone: nil, birthday: nil, age: nil)
    super(id, first_name, last_name, email: email, phone: phone)

    @birthday, @age = birthday, age
  end

  def self.from_partial_data(id: nil, first_name: nil, last_name: nil, 
    email: nil, phone: nil, birthday: nil, age: nil)

    self.new(id, first_name, last_name, 
      email: email, phone: phone, birthday: birthday, age: age)
  end

  def age
    return '' if @age.nil?

    @age.split(/\s(?=\d)/).first
  end
end

class PatientProfile
  attr_reader :patient, :total_appts

  def initialize(patient, total_appts: 0)
    @patient = patient
    @total_appts = total_appts
  end
end