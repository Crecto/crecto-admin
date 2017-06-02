# Crecto Admin

Admin dashboard for Crecto and your database.  Similar to [Rails Admin](https://github.com/sferik/rails_admin) or [Active Admin](https://github.com/activeadmin/activeadmin).

Work in progress.

![crecto admin](http://i.imgur.com/oEoF0ux.png)

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

# add your models
admin_resource(User, Repo)
admin_resource(Project, Repo)

# Right now Crystal Admin is using kemal to render views
Kemal.run
```

To modify the behaviour and display of index, show, form fields and search fields, the following methods can be added to Crecto model classes.  All return an array of string values for fields of the model.

* The attributes shown on the index page:

`def collection_attributes() : Array(String)`

* The attributes show on the show page:

`def show_page_attributes() : Array(String)`

* The attributes in the create and update forms:

`def form_attributes() : Array(String)`

* The attributes used when searching:

`def search_attributes() : Array(String)`

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
