# frozen_string_literal: true

# Temporarily changes Versponse settings inside a block, resetting cached plans and schemas around it
module ConfigurationTestHelper
  def with_configuration(**settings)
    config = Versponse.configuration
    original = settings.keys.to_h { |key| [key, config.instance_variable_get(:"@#{key}")] }
    settings.each { |key, value| config.public_send(:"#{key}=", value) }
    Versponse.reset_caches!
    yield
  ensure
    original&.each { |key, value| config.instance_variable_set(:"@#{key}", value) }
    Versponse.reset_caches!
  end
end
