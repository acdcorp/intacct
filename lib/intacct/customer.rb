module Intacct
  class Customer < Intacct::Base
    def create
      send_xml('create') do |xml|
        xml.function(controlid: "1") {
          xml.send("create_customer") {
            xml.customerid intacct_object_id
            xml.name object.name
            xml.comments
            xml.status "active"
          }
        }
      end

      successful?
    end

    def get *fields
      return false unless object.intacct_system_id.present?

      fields = [
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
      ] if fields.empty?

      send_xml('get') do |xml|
        xml.function(controlid: "f4") {
          xml.get(object: "customer", key: "#{object.intacct_system_id}") {
            xml.fields {
              fields.each do |field|
                xml.field field.to_s
              end
            }
          }
        }
      end

      if successful?
        #get fields
        get_fields = {}
        fields.each do |field|
          get_fields[field.to_sym] = response.at("//customer//#{field.to_s}")&.content
        end
        @data = OpenStruct.new(get_fields)
      end

      successful?
    end

    def update updated_customer = false
      @object = updated_customer if updated_customer
      return false unless object.intacct_system_id.present?

      send_xml('update') do |xml|
        xml.function(controlid: "1") {
          xml.update_customer(customerid: object.intacct_system_id) {
            xml.name object.name
            xml.comments
            xml.status "active"
          }
        }
      end

      successful?
    end

    def delete
      return false unless object.intacct_system_id.present?

      @response = send_xml('delete') do |xml|
        xml.function(controlid: "1") {
          xml.delete_customer(customerid: object.intacct_system_id)
        }
      end

      successful?
    end

    def intacct_object_id
      "#{intacct_customer_prefix}#{object.id}"
    end
  end
end
