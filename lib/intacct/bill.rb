# frozen_string_literal: true

module Intacct
  class Bill < Intacct::Base
    attr_accessor :customer_data
    define_hook :custom_bill_fields, :bill_item_fields

    def create
      raise Intacct::Error.new(message: 'Bill already created on intacct') if object.payment.intacct_system_id.present?

      validate_fields!(:create)

      # Need to create the customer if one doesn't exist
      intacct_customer = Intacct::Customer.new object.customer
      unless object.customer.intacct_system_id.present?
        intacct_customer.create
        object.customer = intacct_customer.object
      end

      if intacct_customer.get
        object.customer = intacct_customer.object
        @customer_data = intacct_customer.data
      end

      # Create vendor if we have one and not in Intacct
      if object.vendor and object.vendor.intacct_system_id.blank?
        intacct_vendor = Intacct::Vendor.new object.vendor
        intacct_vendor.create
        object.vendor = intacct_vendor.object
      end

      content_xml unless @content_xml || @content_xml_block

      send_xml('create') do |xml|
        xml.function(controlid: "f1") {
          xml.send("create_bill") {
            build_content_xml(xml)
            run_hook :custom_bill_fields, xml, self
            run_hook :bill_item_fields, xml, self
          }
        }
      end

      success = successful?

      return true if success

      if !success
        #this invoice already exists... lets grab it and force update
        if resp = @response.at('//result//errorno') and resp.content == "PL01000127"
          intacct_bill_list = Intacct::Bill.new
          intacct_bill_list.get_list(1) do |xml|
            xml.filter {
              xml.expression {
                xml.field "billno"
                xml.operator "="
                xml.value intacct_object_id
              }
            }
          end
          if intacct_bill_list.response and bill_key = intacct_bill_list.response.at("//bill/key").content
            set_intacct_key bill_key
            run_hook :after_send_xml, "create"
            run_hook :after_create
            return true
          end
        end
      end

      success
    end

    def delete
      return false unless object.payment.intacct_system_id.present?

      send_xml('delete') do |xml|
        xml.function(controlid: "1") {
          xml.delete_bill(externalkey: "false", key: object.payment.intacct_key)
        }
      end

      successful?
    end

    def get_list limit=1000

      send_xml('get_list') do |xml|
        xml.function(controlid: "f1") {
          xml.get_list(object: "bill", maxitems: limit) {
            yield xml
          }
        }
      end

      successful?
    end

    def intacct_object_id
      object.payment.intacct_object_id || "#{intacct_bill_prefix}#{object.payment.id}"
    end

    def content_xml(&block)
      if block
        @content_xml_block = block
        return self
      end

      @content_xml = {
        vendorid:    object.vendor.intacct_system_id,
        datecreated: {
          year:  object.payment.created_at.strftime("%Y"),
          month: object.payment.created_at.strftime("%m"),
          day:   object.payment.created_at.strftime("%d")
        },
        dateposted: {
          year:  object.payment.created_at.strftime("%Y"),
          month: object.payment.created_at.strftime("%m"),
          day:   object.payment.created_at.strftime("%d")
        },
        datedue: {
          year:  object.payment.paid_at.strftime("%Y"),
          month: object.payment.paid_at.strftime("%m"),
          day:   object.payment.paid_at.strftime("%d")
        }
      }
    end

    def set_intacct_system_id(_ = nil)
      object.payment.intacct_system_id = intacct_object_id
    end

    def set_intacct_key key
      object.payment.intacct_key = key
    end

    def delete_intacct_system_id(_ = nil)
      object.payment.intacct_system_id = nil
    end

    def delete_intacct_key(_ = nil)
      object.payment.intacct_key = nil
    end

    def set_date_time type
      if %w(create update delete).include? type
        if object.payment.respond_to? :"intacct_#{type}d_at"
          object.payment.send("intacct_#{type}d_at=", Time.zone.now)
        end
        if type == "create" && object.payment.respond_to?(:intacct_updated_at)
          object.payment.intacct_updated_at = Time.zone.now
        end
      end
    end

    private

    def validate_fields!(action)
      object_id_present = (object.payment.respond_to?(:intacct_object_id) && object.payment.intacct_object_id.present?) ||
                          (object.payment.respond_to?(:id) && object.payment.id.present?)
      unless object_id_present
        raise Intacct::Error.new(message: "Bill requires id or intacct_object_id for #{action}")
      end

      required = case action
                 when :create
                   Intacct.intacct_bill_create_required_fields ||
                     Intacct.intacct_bill_required_fields
                 when :update
                   Intacct.intacct_bill_update_required_fields ||
                     Intacct.intacct_bill_create_required_fields ||
                     Intacct.intacct_bill_required_fields
                 end
      required.each do |field|
        unless object.payment.respond_to?(field) && object.payment.send(field).present?
          raise Intacct::Error.new(message: "Bill##{field} is required for #{action} but blank or missing")
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
