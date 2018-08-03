def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  model_attributes = model.fields.map { |f| f[:name] }
  model_attributes.delete(model.primary_key_field_symbol)
  model_attributes.unshift(model.primary_key_field_symbol)

  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes : model_attributes

  form_attributes = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
  if model.responds_to?(:form_attributes)
    form_attributes.concat(model.form_attributes)
  else
    model.fields.each do |f|
      if CrectoAdmin.config.auth_repo == repo && CrectoAdmin.config.auth_model_password == f[:name]
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
          form_attributes << f[:name]
        end
      end
    end
  end

  search_attributes = model.responds_to?(:search_attributes) ? model.search_attributes : model_attributes
  per_page = 20
  resource = {
    model:                 model,
    repo:                  repo,
    model_attributes:      model_attributes,
    collection_attributes: collection_attributes,
    form_attributes:       form_attributes,
  }

  CrectoAdmin.add_resource(resource)

  # Index
  get "/admin/#{model.table_name}" do |ctx|
    accessibility = CrectoAdmin.model_accessibility(ctx, resource)
    next if accessibility[0].nil? || accessibility[1].empty?
    model_query = accessibility[0].as(Crecto::Repo::Query)
    collection_attributes = resource[:collection_attributes].select { |a| accessibility[1].includes? a }
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    query = model_query.limit(per_page).offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, model_query).as(Int64)
    ecr("index")
  end

  # Search
  get "/admin/#{model.table_name}/search" do |ctx|
    accessibility = CrectoAdmin.model_accessibility(ctx, resource)
    next if accessibility[0].nil? || accessibility[1].empty?
    model_query = accessibility[0].as(Crecto::Repo::Query)
    collection_attributes = resource[:collection_attributes].select { |a| accessibility[1].includes? a }
    search_attributes = search_attributes.select { |a| accessibility[1].includes? a }
    search_attributes.delete(model.primary_key_field_symbol)
    search_attributes.unshift(model.primary_key_field_symbol)
    offset = ctx.params.query["offset"]? ? ctx.params.query["offset"].to_i : 0
    search_string = search_attributes.map { |sa| "#{CrectoAdmin.field_cast(sa, repo)} LIKE ?" }.join(" OR ")
    search_params = (1..search_attributes.size).map { |x| "%#{CrectoAdmin.search_param(ctx)}%" }
    query = model_query
      .limit(per_page)
      .where(search_string, search_params)
      .offset(offset)
    data = repo.all(model, query)
    count = repo.aggregate(model, :count, resource[:model].primary_key_field_symbol, model_query).as(Int64)
    ecr("index")
  end

  # New form
  get "/admin/#{model.table_name}/new" do |ctx|
    item = model.new
    ecr("new")
  end

  # View
  get "/admin/#{model.table_name}/:id" do |ctx|
    accessibility = CrectoAdmin.model_accessibility(ctx, resource)
    next if accessibility[0].nil? || accessibility[1].empty?
    model_query = accessibility[0].as(Crecto::Repo::Query)
    query = model_query.where(resource[:model].primary_key_field_symbol, ctx.params.url["id"])
    data = repo.all(model, query).not_nil!
    next if data.empty?
    item = data.first
    model_attributes = accessibility[1]
    ecr("show")
  end

  # Update
  put "/admin/#{model.table_name}/:pid_id" do |ctx|
    item = repo.get!(model, ctx.params.url["pid_id"])
    query_hash = ctx.params.body.to_h
    resource[:form_attributes].each do |attr|
      next if attr.is_a? Symbol
      attr = attr.as(Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))
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
      next if attr.is_a? Symbol
      attr = attr.as(Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String))
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
