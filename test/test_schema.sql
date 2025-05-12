-- Mini-Jane


-- Reset
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;


-- Enum Types
CREATE TYPE appt_status AS ENUM('Not Arrived', 'Arrived', 'Cancelled', 'No Show');


-- Tables
CREATE TABLE users (
  id          serial       PRIMARY KEY,
  first_name  varchar(255) NOT NULL,
  last_name   varchar(255) NOT NULL,
  birthday    date         NOT NULL
  -- Login Info
);

CREATE TABLE patients (
  user_id integer PRIMARY KEY REFERENCES users ON DELETE CASCADE
  -- Other patient-specific info
);

CREATE TABLE staff (
  user_id   integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
  biography text
);

CREATE TABLE disciplines (
  id       serial       PRIMARY KEY,
  name     varchar(255) NOT NULL UNIQUE,
  title    varchar(2),
  clinical boolean      NOT NULL DEFAULT false
);

CREATE TABLE staff_disciplines (
  id            serial  PRIMARY KEY,
  staff_id      integer REFERENCES staff ON DELETE CASCADE NOT NULL,
  discipline_id integer REFERENCES disciplines    ON DELETE CASCADE NOT NULL,
  UNIQUE(staff_id, discipline_id)
);

CREATE TABLE treatments (
  id            serial       PRIMARY KEY,
  name          varchar(255) NOT NULL,
  discipline_id integer      REFERENCES disciplines ON DELETE CASCADE NOT NULL,
  duration      integer      NOT NULL CHECK((duration BETWEEN 5 AND 180) AND (duration % 5 = 0)),
                             -- Only 5-minute intervals, up to 3 hours
  price         money        NOT NULL CHECK(price::numeric >= 0.00),
  UNIQUE(discipline_id, name)
  -- Each discipline can only have one treatment type of the same name
);

CREATE TABLE appointments (
  id            serial  PRIMARY KEY,
  staff_id      integer REFERENCES staff ON DELETE CASCADE NOT NULL,
  patient_id    integer REFERENCES patients ON DELETE CASCADE NOT NULL,
  treatment_id  integer REFERENCES treatments ON DELETE CASCADE NOT NULL,
  "datetime"    timestamp DEFAULT NOW() NOT NULL,
  appt_status   appt_status DEFAULT 'Not Arrived'
);


-- Functions
CREATE OR REPLACE FUNCTION verify_staff_member_offers_treatment() 
RETURNS trigger AS $$
-- Raise error if the staff member does not offer the selected treatment.
  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM staff_disciplines AS sd
      JOIN disciplines ON disciplines.id = sd.discipline_id
      JOIN treatments  ON disciplines.id = treatments.discipline_id
      WHERE sd.staff_id = NEW.staff_id AND treatments.id = NEW.treatment_id
    ) THEN RAISE EXCEPTION 'Cannot book appointment - Staff member does not offer the specified treatment.';
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

-- Raise error if the specified discipline is non-clinical
CREATE OR REPLACE FUNCTION verify_clinical_discipline()
RETURNS trigger AS $$
  BEGIN
    IF (SELECT clinical FROM disciplines WHERE id = NEW.discipline_id) = false
    THEN RAISE EXCEPTION 'Cannot create treatment - Discipline type is non-clinical.';
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;


-- -- Triggers
CREATE OR REPLACE TRIGGER verify_staff_member_offers_treatment 
  BEFORE INSERT ON appointments
  FOR EACH ROW EXECUTE FUNCTION verify_staff_member_offers_treatment();

CREATE OR REPLACE trigger verify_clinical_discipline
  BEFORE INSERT ON treatments
  FOR EACH ROW EXECUTE FUNCTION verify_clinical_discipline();
