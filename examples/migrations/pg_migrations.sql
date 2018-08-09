DROP TABLE IF EXISTS blogs;
DROP TABLE IF EXISTS users;

CREATE TABLE users(
  id BIGSERIAL PRIMARY KEY,
  email character varying NOT NULL,
  encrypted_password character varying,
  role character varying,
  is_active bool,
  name character varying,
  signature TEXT,
  level integer,
  balance float,
  last_posted timestamp without time zone,
  created_at timestamp without time zone,
  updated_at timestamp without time zone
);


CREATE TABLE blogs(
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER references users(id),
  is_public bool,
  title character varying,
  content TEXT,
  created_at timestamp without time zone,
  updated_at timestamp without time zone
);

