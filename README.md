# Crecto Admin

Admin dashboard for Crecto and your database.  Similar to [Rails Admin](https://github.com/sferik/rails_admin) or [Active Admin](https://github.com/activeadmin/activeadmin).

Work in progress.

![crecto admin](screenshot.png)

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  crecto-admin:
    github: Crecto/crecto-admin
```

## Usage

```crystal
require "crecto-admin"

# define Repo and models

# Initialize admin server
init_admin()

# add your models
admin_resource(User, Repo)
admin_resource(Project, Repo)

# Right now Crystal Admin is using kemal to render views
Kemal.run
```

Take a look at the `exmaples` directory to find more infomation about usage.

## Configuration
To modify the behaviour and display of index, form fields and search fields, the following methods can be added to Crecto model classes.

* The attributes shown on the index page:  
  `def self.collection_attributes() : Array(Symbol)`  
  The primary key field will always be shown on the index page.

* The attributes in the create and update forms:  
  `def self.form_attributes() : Array(Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))`  
  Each form attribute could be:
  * `Symbol`: field name
  * `Tuple(Symbol, String)`: {field name, field type}
  * `Tuple(Symbol, String, Array(String))`: {field name, field type, options}
  * `Tuple(Symbol, String, String)`: {field name, field type, option}
  
  Field types:
  * `bool`: checkbox
  * `int`: number input, step 1
  * `float`: number input, step: any
  * `enum`: select from the options (the last item of the tuple)
  * `string`: text input
  * `text`: textarea
  * `password`: password input, the backend will encrypt the raw password into enncrypted password
  * `time`: date time picker
  * `fixed`: readonly input, value as the model value or the option if provided ad the last item of the tuple


* The attributes used when searching:  
  `def self.search_attributes() : Array(Symbol)`  
  The primary key field will always be searched.

## Authentication

#### Database authentication

Add a config block to define some information about your database authentication.

```crystal
CrectoAdmin.config do |config|
  config.auth_enabled = true
  config.auth = CrectoAdmin::DatabaseAuth
  config.auth_repo = Repo
  config.auth_model = User
  config.auth_model_identifier = :email
  config.auth_model_password = :encrypted_password
end
```

#### Basic authentication

```crystal
CrectoAdmin.config do |config|
  config.auth_enabled = true
  config.auth = CrectoAdmin::BasicAuth
  config.basic_auth_credentials = {"user1" => "password1", "user2" => "password2"}
end
```

#### Custom authentication
Config the custom auth method. Return a `nil` or emtpy string for not autherized. Return a nonempty string for authorized.

```crystal
CrectoAdmin.config do |config|
  config.auth_enabled = true
  config.auth = CrectoAdmin::CustomAuth
  c.custom_auth_method = ->(user_identifier : String, password : String) {
    return "autherized user"
  }
end
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/[your-github-name]/CrectoAdmin/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [Nick Franken](https://github.com/fridgerator) - creator, maintainer
