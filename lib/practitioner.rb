class Practitioner
  attr_reader :name
  
  def initialize(id, name)
    @id, @name = id, name
    @appts = []
  end
end