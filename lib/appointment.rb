# Appointments
class Appointment
  def initialize(id, staff, patient, tx_name, tx_duration, date, time)
    @staff, @patient       = staff, patient # Staff and Patient objects
    @tx_name, @tx_duration = tx_name, tx_duration # string/int
    @date, @time           = date, time 
  end
end