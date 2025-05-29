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
