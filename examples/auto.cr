# This will generate the crecto admin code for all tables in the database
# Only works for Mysql database currently
# Redirect the output code to the src folder and run/debug it manually
require "mysql"
require "../src/crecto-admin" # require "crecto-admin" instead if installed crecto-admin

# Setup your repo
module Repo
  extend Crecto::Repo
  config do |conf|
    conf.adapter = Crecto::Adapters::Mysql
    conf.uri = ENV["DATABASE_URL"] # use your database uri
  end
end

# Generate Crystal code
auto_script(Repo)
