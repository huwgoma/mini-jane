class Practitioner
  attr_reader :name

  def initialize(id, name)
    @id, @name = id, name
    @appts = []
  end

  def add_appointments(*appts)
    appts.flatten!
    # Accept either a single appointment or an array of multiple appointments
    # Validate whatever is being passed in
    @appts.push(*appts) 
  end
end