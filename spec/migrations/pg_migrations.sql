DROP TABLE IF EXISTS posts;
DROP TABLE IF EXISTS users;

CREATE TABLE users(
  id BIGSERIAL PRIMARY KEY,
  email character varying NOT NULL,
  encrypted_password character varying,
  status character varying,
  count integer,
  score float,
  is_active bool,
  created_at timestamp without time zone,
  updated_at timestamp without time zone
);


CREATE TABLE posts(
  id BIGSERIAL PRIMARY KEY,
  user_id INTEGER references users(id),
  content TEXT,
  created_at timestamp without time zone,
  updated_at timestamp without time zone
);

