# Before run this example, you need to have the database ready.
# The example below is using the PostgreSQL database.
# If you have not created the database, create it by "psql -c 'create database crecto_admin_test;' -U username"
# If you have not run the migration, then run "psql postgres://username:password@localhost:5432/crecto_admin_test < examples/migrations/pg_migrations.sql"
# Notice that the username and password are the PostgreSQL database username and password
# Then you can run the example directly by "crystal examples/simple.cr"

require "pg"
require "../src/crecto-admin" # require "crecto-admin" instead if installed crecto-admin

# Setup your repo
module Repo
  extend Crecto::Repo
  config do |conf|
    conf.adapter = Crecto::Adapters::Postgres
    conf.uri = ENV["DATABASE_URL"] # use your database uri
  end
end

# Setup your models
class User < Crecto::Model
  schema "users" do
    field :email, String
    field :encrypted_password, String
    field :role, String
    field :is_active, Bool
    field :name, String
    field :signature, String
    field :level, Int32
    field :balance, Float64
    field :last_posted, Time
  end
end

class Blog < Crecto::Model
  schema "blogs" do
    field :user_id, Int32
    field :is_public, Bool
    field :title, String
    field :content, String
  end
end

# Initialize admin server
init_admin()

# Add your models
admin_resource(User, Repo)
admin_resource(Blog, Repo)

# Setup session secret
Kemal::Session.config do |config|
  config.secret = "my super secret"
end

# Run kemal to render views
Kemal.run
