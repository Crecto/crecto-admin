require "kemal"
require "pg"
require "../../crecto/src/crecto"
require "./CrectoAdmin/*"

module CrectoAdmin
  @@resources = Array(NamedTuple(model: Crecto::Model.class, repo: Repo.class)).new

  def self.add_resource(resource)
    @@resources.push({model: resource[:model], repo: resource[:repo]})
  end

  def self.resources
    @@resources
  end
end

get "/" do |ctx|
  ctx.redirect "/dashboard"
end

get "/dashboard" do |ctx|
  render "src/CrectoAdmin/views/dashboard.ecr", "src/CrectoAdmin/views/admin_layout.ecr"
end

def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  CrectoAdmin.add_resource({model: model, repo: repo})

  get "/#{model.table_name}" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    query = Crecto::Repo::Query.limit(20).offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, :id)
    render "src/CrectoAdmin/views/index.ecr", "src/CrectoAdmin/views/admin_layout.ecr"
  end

  get "/#{model.table_name}/:id" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    render "src/CrectoAdmin/views/show.ecr", "src/CrectoAdmin/views/admin_layout.ecr"
  end

  get "/#{model.table_name}/:id/edit" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    render "src/CrectoAdmin/views/edit.ecr", "src/CrectoAdmin/views/admin_layout.ecr"
  end

  delete "/#{model.table_name}/:id" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    repo.delete(item)
    ctx.redirect "/#{model.table_name}"
  end

  put "/#{model.table_name}/:id" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    repo.update(item)
    ctx.redirect "/#{model.table_name}/:id"
  end
end
