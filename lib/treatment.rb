class Treatment
  attr_reader :id, :name, :discipline_id

  def initialize(id, name, discipline_id:, length:, price:)
    @id, @discipline_id = id, discipline_id
    @name = name
    @length, @price = length, price
  end
end