def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes : model.fields.map { |f| f[:name] }
  show_page_attributes = model.responds_to?(:show_page_attributes) ? model.show_page_attributes : model.fields.map { |f| f[:name] }
  form_attributes = model.responds_to?(:form_attributes) ? model.form_attributes : model.fields.map { |f| f[:name] }
  search_attributes = model.responds_to?(:search_attributes) ? model.search_attributes : model.fields.map { |f| f[:name] }
  per_page = 20
  resource = {
    model:                 model,
    repo:                  repo,
    collection_attributes: collection_attributes,
    show_page_attributes:  show_page_attributes,
    form_attributes:       form_attributes,
  }

  CrectoAdmin.add_resource(resource)

  get "/admin/#{model.table_name}" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    query = Crecto::Repo::Query.limit(per_page).offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol).as(Int64)
    ecr("index")
  end

  get "/admin/#{model.table_name}/search" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    search_string = search_attributes.map { |sa| "#{CrectoAdmin.field_cast(model.table_name, repo)} LIKE ?" }.join(" OR ")
    search_params = (1..search_attributes.size).map { |x| "%#{CrectoAdmin.search_param(ctx)}%" }
    query = Crecto::Repo::Query
      .limit(per_page)
      .where(search_string, search_params)
      .offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, Crecto::Repo::Query.where(search_string, search_params)).as(Int64)
    ecr("index")
  end

  get "/admin/#{model.table_name}/new" do |ctx|
    item = model.new
    ecr("new")
  end

  get "/admin/#{model.table_name}/:id" do |ctx|
    if ctx.params.query["_method"]? == "put"
      item = repo.get!(model, ctx.params.url["id"])
      query_hash = ctx.params.query.to_h
      item.class.fields.select { |f| f[:type] == "Bool" }.each do |field|
        query_hash[field[:name].to_s] = query_hash[field[:name].to_s]? == "on" ? "true" : "false"
      end
      item.update_from_hash(query_hash)
      repo.update(item)
      ctx.redirect "/admin/#{model.table_name}/#{item.pkey_value}"
    else
      item = repo.get!(model, ctx.params.url["id"])
      ecr("show")
    end
  end

  put "/admin/#{model.table_name}/:pid_id" do |ctx|
    item = repo.get!(model, ctx.params.url["pid_id"])
    query_hash = ctx.params.body.to_h
    item.class.fields.select { |f| f[:type] == "Bool" }.each do |field|
      query_hash[field[:name].to_s] = query_hash[field[:name].to_s]? == "on" ? "true" : "false"
    end
    item.update_from_hash(query_hash)
    repo.update(item)
    ctx.redirect "/admin/#{model.table_name}/#{item.pkey_value}"
  end

  get "/admin/#{model.table_name}/:id/edit" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    ecr("edit")
  end

  post "/admin/#{model.table_name}" do |ctx|
    item = model.new
    query_hash = ctx.params.body.to_h
    item.class.fields.select { |f| f[:type] == "Bool" }.each do |field|
      query_hash[field[:name].to_s] = query_hash[field[:name].to_s]? == "on" ? "true" : "false"
    end
    item.update_from_hash(query_hash)
    changeset = repo.insert(item)
    # TODO: handle changeset errors
    ctx.redirect "/admin/#{model.table_name}/#{changeset.instance.pkey_value}"
  end

  get "/admin/#{model.table_name}/:id/delete" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    repo.delete(item)
    ctx.redirect "/admin/#{model.table_name}"
  end
end
