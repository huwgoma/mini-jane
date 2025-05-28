class Treatment
  attr_reader :id, :name, :discipline, :length, :price

  def initialize(id, name, discipline:, length:, price:)
    @id = id 
    @discipline = discipline
    @name = name
    @length = length
    @price = price
  end

  def self.from_partial_data(id: nil, name: nil, discipline_id: nil, length: nil, price: nil)
    self.new(id, name, discipline_id: discipline_id, 
             length: length, price: price)
  end

  def self.lengths
    # 5min - 3hr, 5-minute intervals
    (5..180).step(5).to_a
  end 
end