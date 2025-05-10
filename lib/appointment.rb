class Appointment
  def initialize(id, patient, tx_name, tx_length, date_time)
    @id = id
    @patient = patient
    @tx_name, @tx_length = tx_name, tx_length
    @date_time = date_time
  end
end