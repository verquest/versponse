# frozen_string_literal: true

# Stora's verquest custom_field_types (config/initializers/verquest.rb), shared with versponse
STORA_FIELD_TYPES = {
  email: {type: "string", schema_options: {format: "email"}},
  uuid: {type: "string", schema_options: {format: "uuid"}},
  date: {type: "string", schema_options: {format: "date"}},
  datetime: {type: "string", schema_options: {format: "date-time"}},
  url: {type: "string", schema_options: {format: "uri", pattern: "^https://"}},
  site_id: {type: "string", schema_options: {pattern: "^site_"}},
  staff_id: {type: "string", schema_options: {pattern: "^staff_"}},
  unit_id: {type: "string", schema_options: {pattern: "^unit_"}},
  contact_id: {type: "string", schema_options: {pattern: "^con_"}},
  subscription_id: {type: "string", schema_options: {pattern: "^sub_"}},
  tenancy_id: {type: "string", schema_options: {pattern: "^ten_"}},
  task_id: {type: "string", schema_options: {pattern: "^task_"}},
  timeline_source_id: {type: "string", schema_options: {pattern: "^tsrc_"}},
  timeline_template_id: {type: "string", schema_options: {pattern: "^aetpl_"}},
  invoice_id: {type: "string", schema_options: {pattern: "^inv_"}},
  unit_type_id: {type: "string", schema_options: {pattern: "^utype_"}},
  order_id: {type: "string", schema_options: {pattern: "^order_"}},
  stage_id: {type: "string", schema_options: {pattern: "^dstg_"}},
  deal_id: {type: "string", schema_options: {pattern: "^deal_"}},
  protection_level_id: {type: "string", schema_options: {pattern: "^plvl_"}},
  price_adjustment_notification: {
    type: "object",
    schema_options: {
      required: ["notice_period"],
      additionalProperties: false,
      properties: {
        notice_period: {
          oneOf: [
            {type: "integer", minimum: 1, description: "Notice period in days before the adjustment date"},
            {const: "send_immediately", description: "Notify the contact immediately"},
            {type: "null", description: "Do not notify the contact through Stora."}
          ]
        }
      }
    }
  },
  metadata: {type: "object", schema_options: {additionalProperties: {"type" => "string"}, maxProperties: 20}}
}.freeze
