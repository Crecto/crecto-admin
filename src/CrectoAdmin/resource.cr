def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes : model.fields.map { |f| f[:name] }
  show_page_attributes = model.responds_to?(:show_page_attributes) ? model.show_page_attributes : model.fields.map { |f| f[:name] }

  form_attributes = [] of Tuple(Symbol, String) | Tuple(Symbol, String, Array(String))
  if model.responds_to?(:form_attributes)
    form_attributes.concat(model.form_attributes)
  else
    model.fields.each do |f|
      if CrectoAdmin.config.auth_model_password == f[:name]
        form_attributes << {f[:name], "password"}
      else
        attr_type = f[:type].to_s
        if attr_type == "Bool"
          form_attributes << {f[:name], "bool"}
        elsif attr_type.starts_with?("Int")
          form_attributes << {f[:name], "int"}
        elsif attr_type.starts_with?("Float")
          form_attributes << {f[:name], "float"}
        elsif attr_type == "Time"
          form_attributes << {f[:name], "time"}
        else
          form_attributes << {f[:name], "default"}
        end
      end
    end
  end

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

  # Index
  get "/admin/#{model.table_name}" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    query = Crecto::Repo::Query.limit(per_page).offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol).as(Int64)
    ecr("index")
  end

  # Search
  get "/admin/#{model.table_name}/search" do |ctx|
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    search_string = search_attributes.map { |sa| "#{CrectoAdmin.field_cast(sa, repo)} LIKE ?" }.join(" OR ")
    search_params = (1..search_attributes.size).map { |x| "%#{CrectoAdmin.search_param(ctx)}%" }
    query = Crecto::Repo::Query
      .limit(per_page)
      .where(search_string, search_params)
      .offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, Crecto::Repo::Query.where(search_string, search_params)).as(Int64)
    ecr("index")
  end

  # New form
  get "/admin/#{model.table_name}/new" do |ctx|
    item = model.new
    ecr("new")
  end

  # View
  get "/admin/#{model.table_name}/:id" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    ecr("show")
  end

  # Update
  put "/admin/#{model.table_name}/:pid_id" do |ctx|
    item = repo.get!(model, ctx.params.url["pid_id"])
    query_hash = ctx.params.body.to_h
    resource[:form_attributes].each do |attr|
      if attr[1] == "bool"
        query_hash[attr[0].to_s] = query_hash[attr[0].to_s]? == "on" ? "true" : "false"
      elsif attr[1] == "password"
        new_password = query_hash[attr[0].to_s]
        if new_password.empty?
          query_hash.delete(attr[0].to_s)
        else
          encrypted_password = Crypto::Bcrypt::Password.create(new_password)
          query_hash[attr[0].to_s] = encrypted_password.to_s
        end
      end
    end
    item.update_from_hash(query_hash)
    changeset = repo.update(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("edit")
    else
      ctx.flash["success"] = "Updated successfully"
      ctx.redirect "/admin/#{model.table_name}/#{item.pkey_value}"
    end
  end

  # Edit form
  get "/admin/#{model.table_name}/:id/edit" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    ecr("edit")
  end

  # Create
  post "/admin/#{model.table_name}" do |ctx|
    puts "create"
    item = model.new
    query_hash = ctx.params.body.to_h
    resource[:form_attributes].each do |attr|
      if attr[1] == "bool"
        query_hash[attr[0].to_s] = query_hash[attr[0].to_s]? == "on" ? "true" : "false"
      elsif attr[1] == "password"
        new_password = query_hash[attr[0].to_s]
        if new_password.empty?
          query_hash.delete(attr[0].to_s)
        else
          encrypted_password = Crypto::Bcrypt::Password.create(new_password)
          query_hash[attr[0].to_s] = encrypted_password.to_s
        end
      end
    end
    item.update_from_hash(query_hash)
    changeset = repo.insert(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("new")
    else
      ctx.flash["success"] = "Created sucessfully"
      ctx.redirect "/admin/#{model.table_name}/#{changeset.instance.pkey_value}"
    end
  end

  # Delete
  get "/admin/#{model.table_name}/:id/delete" do |ctx|
    item = repo.get!(model, ctx.params.url["id"])
    changeset = repo.delete(item)

    if changeset.errors.any?
      ctx.flash["error"] = CrectoAdmin.changeset_errors(changeset)
      ecr("show")
    else
      ctx.flash["success"] = "Deleted successfully"
      ctx.redirect "/admin/#{model.table_name}"
    end
  end
end
