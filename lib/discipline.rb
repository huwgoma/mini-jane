class Discipline
  attr_reader :id, :name
  
  def initialize(id, name)
    @id, @name = id, name
  end

  def to_s
    name
  end
end