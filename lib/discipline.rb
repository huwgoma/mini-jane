class Discipline
  attr_reader :id, :name, :title
  
  def initialize(id:, name:, title:)
    @id, @name, @title = id, name, title
  end

  def self.from_partial_data(id: nil, name: nil, title: nil)
    self.new(id: id, name: name, title: title)
  end

  def to_s
    name
  end
end