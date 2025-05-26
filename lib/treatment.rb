class Treatment
  attr_reader :id, :name, :discipline_id, :length, :price

  def initialize(id, name, discipline_id:, length:, price:)
    @id, @discipline_id = id, discipline_id
    @name = name
    @length = length
    @price = price
  end

  def self.lengths
    # 5min - 3hr, 5-minute intervals
    (5..180).step(5).to_a
  end
end