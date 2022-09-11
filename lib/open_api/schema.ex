defmodule OpenAPI.Schema do
  require EEx

  alias OpenAPI.Spec

  @file_base "lib/example/schemas"
  @module_base Example

  @replace [
    {~r/^Codespaces/, "Codespace"},
    {~r/Oidc/, "OIDC"},
    {~r/^Scim/, "SCIM"},
    {~r/^Ssh/, "SSH"}
  ]

  @skip [
    # ~r/^Nullable/
  ]

  @namespace [
    Actions,
    AdvancedSecurity,
    Branch,
    Check,
    CodeOfConduct,
    CodeScanning,
    Codespace,
    Commit,
    Content,
    Deployment,
    Gist,
    Hook,
    Installation,
    Issue,
    License,
    Marketplace,
    Organization,
    Project,
    ProtectedBranch,
    PullRequest,
    Release,
    Repository,
    Runner,
    SCIM,
    Team,
    Timeline,
    User,
    Webhook,
    Workflow
  ]

  def write_all(spec) do
    File.mkdir_p!(@file_base)
    schemas = Enum.take(spec.components.schemas, 2)

    for {name, schema} <- schemas do
      name =
        name
        |> String.replace("-", "_")
        |> Macro.camelize()
        |> replace()
        |> namespace()

      unless primitive_type?(schema) or schema_skipped?(name) do
        write(name, schema)
      end
    end
  end

  def write(name, schema) do
    module = Module.concat(@module_base, name)
    filename = Macro.underscore(name)
    docstring = docstring(schema)
    types = types(schema)
    fields = fields(schema)
    decoders = decoders(schema)

    file =
      render(
        module: module,
        docstring: docstring,
        types: types,
        fields: fields,
        decoders: decoders
      )
      |> Code.format_string!()

    location = Path.join(@file_base, filename <> ".ex")
    File.mkdir_p!(Path.dirname(location))
    File.write!(location, [file, "\n"])
    {location, name}
  end

  defp replace(schema_name) do
    Enum.reduce(@replace, schema_name, fn {pattern, replacement}, name ->
      String.replace(name, pattern, replacement)
    end)
  end

  defp primitive_type?(%Spec.Schema{type: "array"}), do: true
  defp primitive_type?(%Spec.Schema{type: "boolean"}), do: true
  defp primitive_type?(%Spec.Schema{type: "integer"}), do: true
  defp primitive_type?(%Spec.Schema{type: "string"}), do: true
  defp primitive_type?(_), do: false

  defp schema_skipped?(schema_name) do
    Enum.any?(@skip, fn
      %Regex{} = regex -> Regex.match?(regex, schema_name)
      ^schema_name -> true
      _ -> false
    end)
  end

  defp namespace(schema_name) do
    Enum.find_value(@namespace, schema_name, fn namespace ->
      namespace = inspect(namespace)

      if String.starts_with?(schema_name, namespace) do
        Enum.join([namespace, String.trim_leading(schema_name, namespace)], ".")
        |> String.trim_trailing(".")
      end
    end)
  end

  defp docstring(%Spec.Schema{title: title, description: description}) do
    """
    #{title || description}

    Generated by OpenAPI Generator. Avoid editing this file directly.\
    """
  end

  defp types(%Spec.Schema{properties: properties}) do
    Enum.map(properties, fn {name, spec_or_ref} ->
      {name, type(spec_or_ref)}
    end)
    |> Enum.sort_by(fn {name, _type} -> name end)
  end

  defp type(%Spec.Schema{type: "array", items: items}) do
    ["[", type(items), "]"]
  end

  defp type(%Spec.Schema{type: "boolean"}), do: "boolean"
  defp type(%Spec.Schema{type: "integer"}), do: "integer"
  defp type(%Spec.Schema{type: "object"}), do: "map"
  defp type(%Spec.Schema{type: "string"}), do: "String.t()"

  defp type(%Spec.Ref{"$ref": "#/components/schemas/" <> schema_name}) do
    schema_module =
      schema_name
      |> String.replace("-", "_")
      |> Macro.camelize()
      |> replace()
      |> namespace()

    Module.concat(@module_base, schema_module)
    |> inspect()
    |> to_string()
    |> Kernel.<>(".t()")
  end

  defp fields(%Spec.Schema{properties: properties}) do
    Enum.map(properties, fn {name, _spec_or_ref} -> name end)
    |> Enum.sort()
  end

  defp decoders(%Spec.Schema{properties: properties}) do
    Enum.map(properties, fn {name, spec_or_ref} ->
      decoder =
        decoder(name, spec_or_ref)
        |> Macro.to_string()

      {name, decoder}
    end)
    |> Enum.sort_by(fn {name, _decoder} -> name end)
  end

  defp decoder(_name, %Spec.Schema{type: "array", items: _items}) do
    quote do
      nil
    end
  end

  defp decoder(name, %Spec.Schema{type: _}) do
    quote do
      value[unquote(name)]
    end
  end

  defp decoder(name, %Spec.Ref{"$ref": "#/components/schemas/" <> schema_name}) do
    schema_module =
      schema_name
      |> String.replace("-", "_")
      |> Macro.camelize()
      |> replace()
      |> namespace()

    mod = Module.concat(@module_base, schema_module)

    quote do
      unquote(mod).decode(value[unquote(name)])
    end
  end

  path = :code.priv_dir(:open_api) |> Path.join("templates/schema.eex")
  EEx.function_from_file(:defp, :render, path, [:assigns])
end
