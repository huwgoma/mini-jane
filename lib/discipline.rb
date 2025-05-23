class Discipline
  attr_reader :id, :name, :title
  
  def initialize(id, name, title)
    @id, @name, @title = id, name, title
  end

  def to_s
    name
  end
end