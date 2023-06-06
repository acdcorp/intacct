module Intacct
  class NewCustomer < NewBase
    FIELDS = [
      :customerid,
      :name,
      :termname,
      :auto_employee,
      :auto_commission_start_date,
      :auto_commission_end_date,
      :auto_commission_rate,
      :property_employee,
      :property_commission_start_date,
      :property_commission_end_date,
      :property_commission_rate,
      :subro_employee,
      :subro_commission_start_date,
      :subro_commission_end_date,
      :subro_commission_rate
    ]

    after_get :collect_data_fields

    def self.create(customer)
      intacct_object_id = "#{Intacct.customer_prefix}#{customer.customerid}".freeze
      intacct_api = IntacctApi::CreateCustomer.
        new(intacct_object_id: intacct_object_id,
            fields: customer.intacct_fields)
      intacct_api.build_xml
      intacct_customer = new(intacct_api: intacct_api, intacct_action: 'create')
      intacct_customer.valid_intacct_fields?(customer.intacct_fields)
      intacct_customer.send_xml
      intacct_customer
    end

    def self.get(intacct_key)
      intacct_api = IntacctApi::GetCustomer.
        new(intacct_key: intacct_key, fields: fields)
      intacct_customer = new(intacct_api: intacct_api, intacct_action: 'get')
      intacct_customer.send_xml
      intacct_customer
    end


    def valid_intacct_fields?(intacct_fields)
      intacct_fields.keys.sort === FIELDS.sort
    end

    def collect_data_fields(response)
      OpenStruct.new (
        fields.map do |field|
          [
            field,
            response.at("//customer//#{field.to_s}")&.content
          ]
        end.to_h
      )
    end

    def action_error_validation
      "Invalid Customer data, it requires: customer with FIELDS: ->Help -> query FIELDS constant"
    end
  end
end
