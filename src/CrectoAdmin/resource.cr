def self.admin_resource(model : Crecto::Model.class, repo, **opts)
  model_attributes = model.fields.map { |f| f[:name] }
  model_attributes.delete(model.primary_key_field_symbol)
  model_attributes.unshift(model.primary_key_field_symbol)

  collection_attributes = model.responds_to?(:collection_attributes) ? model.collection_attributes : model_attributes

  form_attributes = [] of Symbol | Tuple(Symbol, String) | Tuple(Symbol, String, Array(String) | String)
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
        form_attributes << f[:name]
      end
    end
  end

  if model.responds_to?(:form_attributes)
    form_attributes = CrectoAdmin.merge_form_attributes(model.form_attributes, form_attributes)
  else
    form_attributes = form_attributes.select do |a|
      next a != model.primary_key_field_symbol if a.is_a? Symbol
      a[0] != model.primary_key_field_symbol
    end
  end

  search_attributes = model.responds_to?(:search_attributes) ? model.search_attributes : model_attributes

  resource_index = CrectoAdmin.resources.size

  resource = {
    index:                 resource_index,
    model:                 model,
    repo:                  repo,
    model_attributes:      model_attributes,
    collection_attributes: collection_attributes,
    form_attributes:       form_attributes,
    search_attributes:     search_attributes,
  }

  CrectoAdmin.add_resource(resource)
end
