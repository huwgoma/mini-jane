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
  email       varchar(50),
  phone       varchar(50)
  -- Login Info
);

CREATE TABLE patients (
  user_id integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
  birthday    date
  -- Other patient-specific info
);

CREATE TABLE staff (
  user_id   integer PRIMARY KEY REFERENCES users ON DELETE CASCADE,
  biography text
);

CREATE TABLE disciplines (
  id       serial       PRIMARY KEY,
  name     varchar(255) NOT NULL UNIQUE,
  title    varchar(2)
);

CREATE TABLE staff_disciplines (
  id            serial  PRIMARY KEY,
  staff_id      integer REFERENCES staff ON DELETE CASCADE NOT NULL,
  discipline_id integer REFERENCES disciplines ON DELETE CASCADE NOT NULL,
  UNIQUE(staff_id, discipline_id)
);

CREATE TABLE treatments (
  id            serial       PRIMARY KEY,
  name          varchar(255) NOT NULL,
  discipline_id integer      REFERENCES disciplines ON DELETE CASCADE NOT NULL,
  length      integer        NOT NULL CHECK((length BETWEEN 5 AND 180) AND (length % 5 = 0)),
                             -- Only 5-minute intervals, up to 3 hours
  price         money        NOT NULL CHECK(price::numeric >= 0.00) DEFAULT 0.00,
  UNIQUE(discipline_id, name)
  -- Each discipline can only have one treatment type of the same name
);

CREATE TABLE appointments (
  id            serial  PRIMARY KEY,
  staff_id      integer REFERENCES staff ON DELETE CASCADE NOT NULL,
  patient_id    integer REFERENCES patients ON DELETE CASCADE NOT NULL,
  treatment_id  integer REFERENCES treatments ON DELETE CASCADE NOT NULL,
  datetime      timestamp DEFAULT NOW() NOT NULL,
  status        appt_status DEFAULT 'Not Arrived'
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


-- Triggers
CREATE OR REPLACE TRIGGER verify_staff_member_offers_treatment 
  BEFORE INSERT ON appointments
  FOR EACH ROW EXECUTE FUNCTION verify_staff_member_offers_treatment();


-- -- Seed
-- INSERT INTO users (first_name, last_name, email, phone)
-- VALUES ('Hugo',    'Ma',      'huwgoma@gmail.com',      6476758914), 
--        ('Annie',   'Hu',      'hu.annie06@gmail.com',   6476089210), 
--        ('Kevin',   'Ho',      'kevinnnho@gmail.com',    6475338232), 
--        ('Alan',    'Mitri',   'alan.mitri@hotmail.com', NULL      ), 
--        ('Alexis',  'Butler',  'alexiss@gmail.com',      9059737080), 
--        ('Hendrik', 'Swart',    NULL,                    NULL      ), 
--        ('Phil',    'Genesis',  NULL,                    4165506666),
--        ('Carol',   'Scott',    NULL,                    NULL      ), 
--        ('Dan',     'Torres',   NULL,                    NULL      ),
--        ('Jeff',    'Leps',     NULL,                    NULL      ); 

-- INSERT INTO staff (user_id, biography)
-- VALUES (1, ''),             -- Hugo
--        (2, ''),             -- Annie
--        (3, ''),             -- Kevin
--        (4, ''),             -- Alan
--        (5, ''),             -- Alexis
--        (7, 'Owner of SJV'); -- Phil

-- INSERT INTO patients (user_id, birthday)
-- VALUES (1,  '1997-09-14'),  -- Hugo
--        (6,  '1930-05-04'),  -- Hendrik
--        (8,  '1978-03-14'),  -- Carol
--        (9,  '1990-08-24'),  -- Dan
--        (10, '1975-10-29'); -- Jeff

-- INSERT INTO disciplines (name, title)
-- VALUES ('Physiotherapy',   'PT'),
--        ('Massage Therapy', 'MT'),
--        ('Chiropractic',    'DC');
       
-- INSERT INTO staff_disciplines(staff_id, discipline_id)
-- VALUES (2, 1),         -- Annie  -> PT
--        (3, 1),         -- Kevin  -> PT
--        (4, 2),         -- Alan   -> MT
--        (5, 3),         -- Alexis -> DC
--        (7, 1), (7, 3); -- Phil   -> PT, Chiro

-- INSERT INTO treatments(name, discipline_id, length, price)
-- VALUES ('PT - Initial',   1, 45, 100.00),
--        ('PT - Treatment', 1, 30, 85.00),
--        ('MT - 30 mins',   2, 30, 75.00),
--        ('MT - 45 mins',   2, 45, 100.00),
--        ('MT - 60 mins',   2, 60, 120.00),
--        ('DC - Initial',   3, 40, 120.00),
--        ('DC - Treatment', 3, 20, 75.00);

-- INSERT INTO appointments(staff_id, patient_id, treatment_id, "datetime")
-- VALUES -- Fixed Date (Oct 08, 2025)
--        (2, 1, 1,  '2025-10-08 10:00AM'), -- Annie / Hugo / PT Ax
--        (2, 8, 2,  '2025-10-08 11:00AM'), -- Annie / Carol / PT Tx
--        (3, 6, 2,  '2025-10-08 2:00PM'),  -- Kevin / Hendrik / PT Tx
--        (7, 10, 2, '2025-10-08 10:00AM'), -- Phil / Jeff / PT Tx
--        (4, 10, 4, '2025-10-08 11:00AM'), -- Alan / Jeff / MT 45
--        (5, 10, 7, '2025-10-08 12:00PM'), -- Alexis / Jeff / DC Tx
--        -- Yesterday
--        (2, 1, 1,  CURRENT_DATE - 1 + '9:00AM'::time),  -- Annie / Hugo / PT Ax
--        (2, 8, 2,  CURRENT_DATE - 1 + '10:00AM'::time), -- Annie / Carol / PT Tx
--        (3, 6, 2,  CURRENT_DATE - 1 + '1:00PM'::time),  -- Kevin / Hendrik / PT Tx
--        (7, 10, 2, CURRENT_DATE - 1 + '9:00AM'::time),  -- Phil / Jeff / PT Tx
--        (4, 10, 4, CURRENT_DATE - 1 + '10:00AM'::time), -- Alan / Jeff / MT 45
--        (5, 10, 7, CURRENT_DATE - 1 + '11:00AM'::time), -- Alexis / Jeff / DC Tx
--        -- Today
--        (2, 1, 1,  CURRENT_DATE + '10:00AM'::time), -- Annie / Hugo / PT Ax
--        (2, 8, 2,  CURRENT_DATE + '11:00AM'::time), -- Annie / Carol / PT Tx
--        (3, 6, 2,  CURRENT_DATE + '2:00PM'::time),  -- Kevin / Hendrik / PT Tx
--        (7, 10, 2, CURRENT_DATE + '10:00AM'::time), -- Phil / Jeff / PT Tx
--        (4, 10, 4, CURRENT_DATE + '11:00AM'::time), -- Alan / Jeff / MT 45
--        (5, 10, 7, CURRENT_DATE + '12:00PM'::time), -- Alexis / Jeff / DC Tx
--        -- Tomorrow
--        (2, 1, 1,  CURRENT_DATE + 1 + '11:00AM'::time), -- Annie / Hugo / PT Ax
--        (2, 8, 2,  CURRENT_DATE + 1 + '12:00PM'::time), -- Annie / Carol / PT Tx
--        (3, 6, 2,  CURRENT_DATE + 1 + '3:00PM'::time),  -- Kevin / Hendrik / PT Tx
--        (7, 10, 2, CURRENT_DATE + 1 + '11:00AM'::time), -- Phil / Jeff / PT Tx
--        (4, 10, 4, CURRENT_DATE + 1 + '12:00PM'::time), -- Alan / Jeff / MT 45
--        (5, 10, 7, CURRENT_DATE + 1 + '1:00PM'::time);  -- Alexis / Jeff / DC Tx