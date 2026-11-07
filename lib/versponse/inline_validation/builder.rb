# frozen_string_literal: true

module Versponse
  module InlineValidation
    # Turns a plan into one that validates while rendering, when its validation schema proves it can: the object
    # keywords hold by construction (a plan writes exactly its steps' String keys, unconditional ones always), and
    # each step checks its value. Nested plans are proven against their subschema in the same tree; anything
    # unproven checks its written value with the subschema's compiled checker.
    #
    # @api private
    class Builder
      # Object keywords a plan guarantees by construction (type object, additionalProperties false)
      OBJECT_KEYWORDS = %w[type properties required additionalProperties].freeze

      # Types whose values can't be changed in place later in the render (Strings aside, see the README)
      SCALAR_TYPES = %w[string number integer boolean null].freeze

      # Keywords that never change validity, besides x- extensions
      INERT = (Validator::Compiler::ANNOTATIONS + Validator::Compiler::ANCHORS).freeze

      # @param compiler [Versponse::Validator::Compiler] compiler that compiled the whole validation schema
      def initialize(compiler)
        @compiler = compiler
      end

      # @param plan [Versponse::Plan] plain plan
      # @param schema [Hash] its object schema, from the compiled tree
      # @return [Versponse::Plan, nil] the validating plan, nil when the schema doesn't prove it
      def prove(plan, schema)
        return unless object_schema?(schema)

        properties = schema.fetch("properties", {})
        keys = plan.steps.map(&:key)
        return unless keys.uniq.size == keys.size && keys.sort == properties.keys.sort
        return unless plan.steps.reject(&:conditional?).map(&:key).sort == schema.fetch("required", []).sort

        steps = plan.steps.map { |step| checked(step, properties.fetch(step.key)) }
        Plan.new(label: plan.label, steps:) unless steps.include?(nil)
      rescue Validator::Compiler::Unsupported
        nil
      end

      private

      def object_schema?(schema)
        schema.is_a?(Hash) && schema["type"] == "object" && schema["additionalProperties"] == false &&
          schema.each_key.all? { |key| OBJECT_KEYWORDS.include?(key) || inert?(key) }
      end

      def inert?(key)
        INERT.include?(key) || key.start_with?("x-")
      end

      # Only these keys, besides inert ones
      def only?(schema, keys)
        schema.is_a?(Hash) && schema.each_key.all? { |key| keys.include?(key) || inert?(key) }
      end

      def checked(step, schema)
        case step
        when Steps::Read, Steps::Value then step.checked(@compiler.checker_for(schema), recheck: !scalar?(schema))
        when Steps::Const then step if root(schema).valid?(step.value)
        when Steps::Nested then nested(step, schema)
        when Steps::OneOf then Steps::Checked.new(step, root(schema))
        end
      end

      # A schema whose accepted values are never an Array or Hash needs no recheck after the render
      def scalar?(schema)
        schema.is_a?(Hash) && schema.key?("type") && Array(schema["type"]).all? { |type| SCALAR_TYPES.include?(type) }
      end

      def root(schema)
        Validator::Root.new(@compiler.checker_for(schema))
      end

      def nested(step, schema)
        target = step.collection? ? items(schema) : schema
        plans = step.plans.map { |plan| proven(plan, target) } if target
        return Steps::Checked.new(step, root(schema)) if plans.nil? || plans.include?(nil)

        step.with_plans(plan: plans[0], collapsed_plan: plans[1], nil_fails: !root(schema).valid?(nil))
      end

      # {"type" => "array" or ["array", "null"], "items" => I}: the items schema I
      def items(schema)
        return unless only?(schema, %w[type items]) && schema.key?("items")

        schema["items"] if [["array"], %w[array null]].include?(Array(schema["type"]).sort)
      end

      # The schema itself, or a branch of an anyOf (any branch passing satisfies it)
      def proven(plan, schema)
        plan = resolve(plan)
        return unless plan

        prove(plan, schema) || (schema["anyOf"].lazy.filter_map { |branch| prove(plan, branch) }.first if only?(schema, %w[anyOf]) && schema["anyOf"].is_a?(Array))
      end

      # Class-backed and inline plans; dispatchers and other plan objects stay unproven
      def resolve(plan)
        case plan
        when Plan then plan
        when LazyPlan then plan.resolve
        end
      rescue Error
        nil
      end
    end
  end
end
