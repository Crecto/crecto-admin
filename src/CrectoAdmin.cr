require "kemal"
require "pg"
require "../../crecto/src/crecto"
require "./CrectoAdmin/*"

module CrectoAdmin
  @@resources = Array(NamedTuple(
    model: Crecto::Model.class,
    repo: Repo.class,
    collection_attributes: Array(Symbol),
    show_page_attributes: Array(Symbol),
    form_attributes: Array(Symbol))).new

  def self.add_resource(resource)
    @@resources.push(resource)
  end

  def self.resources
    @@resources
  end

  def self.resource(model)
    @@resources.select{|r| r[:model] == model }[0]
  end
end

get "/admin" do |ctx|
  ctx.redirect "/admin/dashboard"
end

get "/admin/dashboard" do |ctx|
  render "src/views/dashboard.ecr", "src/views/admin_layout.ecr"
end

def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes :  model.fields.map{|f| f[:name] }
  show_page_attributes = model.responds_to?(:show_page_attributes) ? model.show_page_attributes :  model.fields.map{|f| f[:name] }
  form_attributes = model.responds_to?(:form_attributes) ? model.form_attributes :  model.fields.map{|f| f[:name] }

  resource = {
    model: model,
    repo: repo,
    collection_attributes: collection_attributes,
    show_page_attributes: show_page_attributes,
    form_attributes: form_attributes}

  CrectoAdmin.add_resource(resource)

  get "/admin/#{model.table_name}" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    query = Crecto::Repo::Query.limit(20).offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, :id)
    render "src/views/index.ecr", "src/views/admin_layout.ecr"
  end

  get "/admin/#{model.table_name}/:id" do |ctx|
    if ctx.params.query["_method"]? == "put"
      item = repo.get!(model, ctx.params.url["id"])
      query_hash = ctx.params.query.to_h
      item.class.fields.select{|f| f[:type] == "Bool"}.each do |field|
        query_hash[field[:name].to_s] = query_hash[field[:name].to_s]? == "on" ? "true" : "false"
      end
      item.update_from_hash(query_hash)
      repo.update(item)
      ctx.redirect "/admin/#{model.table_name}/#{item.id}"
    else
      item = repo.get!(model, ctx.params.url["id"])
      render "src/views/show.ecr", "src/views/admin_layout.ecr"
    end
  end

  get "/admin/#{model.table_name}/:id/edit" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    render "src/views/edit.ecr", "src/views/admin_layout.ecr"
  end

  delete "/admin/#{model.table_name}/:id" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    repo.delete(item)
    ctx.redirect "/admin/#{model.table_name}"
  end
end
