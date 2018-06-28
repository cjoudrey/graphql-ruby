class GraphQLCatsSchemaResolver
  def initialize(data)
    @data = data
  end

  def call(type, field, obj, args, ctx)
    value = obj[field.name] if obj
    value = expand_refs(value)
    value = apply_directives(value, args, ctx, field.ast_node.directives)

    value
  end

  def resolve_type(type, obj, ctx)
    ctx.schema.find(obj["type"])
  end

  private

  def expand_refs(value)
    if value.is_a?(Array)
      value.map { |value| expand_ref(value) }
    else
      expand_ref(value)
    end
  end

  def expand_ref(value)
    if value.is_a?(Hash) && value["$ref"]
      @data[value["$ref"]]
    else
      value
    end
  end

  def apply_directives(previous_value, args, context, directive_nodes)
    value = previous_value

    directive_nodes.each do |directive_node|
      directive_arguments = Hash[directive_node.arguments.map { |argument| [argument.name, argument.value] }]

      value = case directive_node.name
      when "resolveString"
        value = directive_arguments["value"]
        args.each do |(arg_name, arg_value)|
          value = value.gsub("$#{arg_name}", arg_value.to_s)
        end
        value
      when "resolvePromise"
        LazyHelpers::Wrapper.new(value)
      when "resolvePromiseString"
        LazyHelpers::Wrapper.new(directive_arguments["value"])
      when "resolvePromiseReject"
        LazyHelpers::Wrapper.new do
          raise GraphQL::ExecutionError.new(directive_arguments["message"])
        end
      when "resolvePromiseRejectList"
        LazyHelpers::Wrapper.new do
          directive_arguments["messages"].each do |error_message|
            context.add_error(GraphQL::ExecutionError.new(error_message))
          end

          directive_arguments["values"]
        end
      when "resolveEmptyObject"
        {}
      when "resolveError"
        raise GraphQL::ExecutionError.new(directive_arguments["message"])
      when "resolveErrorList"
        directive_arguments["messages"].each do |error_message|
          context.add_error(GraphQL::ExecutionError.new(error_message))
        end

        directive_arguments["values"]
      when "argumentsJson"
        args.to_h.to_json
      else
        raise "Unsupported directive: #{directive_node.name}"
      end
    end

    value
  end
end
