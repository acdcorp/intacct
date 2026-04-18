# frozen_string_literal: true
module Intacct
  class Customer < Intacct::Base
    define_hook :custom_customer_fields

    def create
      validate_fields!(:create)
      content_xml unless @content_xml || @content_xml_block

      send_xml('create') do |xml|
        xml.function(controlid: '1') {
          xml.send('create_customer') {
            xml.customerid intacct_object_id
            build_content_xml(xml)
            run_hook :custom_customer_fields, xml
          }
        }
      end

      successful?
    end

    def get *fields
      return false unless object.intacct_system_id.present?

      fields = Intacct.customer_fields if fields.empty?

      send_xml('get') do |xml|
        xml.function(controlid: 'f4') {
          xml.get(object: 'customer', key: "#{object.intacct_system_id}") {
            xml.fields {
              fields.each do |field|
                xml.field field.to_s
              end
            }
          }
        }
      end

      if successful?
        get_fields = {}
        fields.each do |field|
          get_fields[field.to_sym] = response.at("//customer//#{field.to_s}")&.content
        end
        @data = OpenStruct.new(get_fields)
      end

      successful?
    end

    def update(updated_customer = false)
      @object = updated_customer if updated_customer
      return false unless object.intacct_system_id.present?

      validate_fields!(:update)
      content_xml unless @content_xml || @content_xml_block

      send_xml('update') do |xml|
        xml.function(controlid: '1') {
          xml.update_customer(customerid: object.intacct_system_id) {
            build_content_xml(xml)
            run_hook :custom_customer_fields, xml
          }
        }
      end

      successful?
    end

    def delete
      return false unless object.intacct_system_id.present?

      @response = send_xml('delete') do |xml|
        xml.function(controlid: '1') {
          xml.delete_customer(customerid: object.intacct_system_id)
        }
      end

      successful?
    end

    def intacct_object_id
      object.intacct_object_id || "#{intacct_customer_prefix}#{object.id}"
    end

    def content_xml(&block)
      if block
        @content_xml_block = block
        return self
      end

      @content_xml = {
        name:     object.name,
        comments: nil,
        status:   'active'
      }
    end

    private

    def validate_fields!(action)
      required = case action
                 when :create
                   Intacct.intacct_customer_create_required_fields ||
                     Intacct.intacct_customer_required_fields
                 when :update
                   Intacct.intacct_customer_update_required_fields ||
                     Intacct.intacct_customer_create_required_fields ||
                     Intacct.intacct_customer_required_fields
                 end
      required.each do |field|
        unless object.respond_to?(field) && object.send(field).present?
          raise Intacct::Error.new(message: "Customer##{field} is required for #{action} but blank or missing")
        end
      end
    end

    def build_content_xml(xml)
      if @content_xml_block
        @content_xml_block.call(xml)
      else
        hash_to_xml(xml, @content_xml)
      end
    end

    def hash_to_xml(xml, hash)
      hash.each do |key, value|
        if value.is_a?(Hash)
          xml.send(key) { hash_to_xml(xml, value) }
        else
          xml.send(key, value)
        end
      end
    end
  end
end
