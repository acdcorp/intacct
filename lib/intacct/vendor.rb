# frozen_string_literal: true

module Intacct
  class Vendor < Base
    define_hook :custom_vendor_fields

    def create
      validate_fields!(:create)
      content_xml unless @content_xml || @content_xml_block

      send_xml('create') do |xml|
        xml.function(controlid: "1") {
          xml.create_vendor {
            xml.vendorid intacct_object_id
            build_content_xml(xml)
            run_hook :custom_vendor_fields, xml, self
          }
        }
      end

      success = successful?

      return true if success

      if !success
        error_codes = @response.search('//result//errorno').map(&:content)

        if error_codes.include?(Intacct.duplicate_transaction_error_code) ||
           error_codes.include?(Intacct.duplicate_contact_error_code)
          set_intacct_system_id
          run_hook :after_send_xml, 'create'
          run_hook :after_create, self
          return true
        end
      end

      success
    end

    def update(updated_vendor = false)
      @object = updated_vendor if updated_vendor
      return false if object.intacct_system_id.nil?

      validate_fields!(:update)
      content_xml unless @content_xml || @content_xml_block

      send_xml('update') do |xml|
        xml.function(controlid: "1") {
          xml.update_vendor(vendorid: object.intacct_system_id) {
            build_content_xml(xml)
            run_hook :custom_vendor_fields, xml, self
          }
        }
      end

      successful?
    end

    def delete
      return false if object.intacct_system_id.nil?

      @response = send_xml('delete') do |xml|
        xml.function(controlid: '1') {
          xml.delete_vendor(vendorid: object.intacct_system_id)
        }
      end

      successful?
    end

    def intacct_object_id
      object.intacct_object_id || "#{intacct_vendor_prefix}#{object.id}"
    end

    def content_xml(&block)
      if block
        @content_xml_block = block
        return self
      end

      contact = {
        contactname: object.contactname,
        printas:     object.full_name,
        companyname: object.company_name,
        firstname:   object.first_name,
        lastname:    object.last_name,
        phone1:      object.business_phone,
        cellphone:   object.cell_phone,
        email1:      object.email
      }

      if object.billing_address.present?
        mailaddr = {
          address1: object.billing_address.address1,
          city:     object.billing_address.city,
          state:    object.billing_address.state,
          zip:      object.billing_address.zipcode
        }
        mailaddr[:address2] = object.billing_address.address2 if object.billing_address.address2.present?
        contact[:mailaddress] = mailaddr
      end

      ach_complete = %i[ach_routing_number ach_account_number ach_account_type ach_remittance_type].all? do |f|
        object.respond_to?(f) && object.send(f).present?
      end

      @content_xml = { name: object.name, vendtype: 'Appraiser', taxid: object.tax_number }

      if ach_complete
        @content_xml[:paymethod] = (object.respond_to?(:paymethod) && object.paymethod.present?) ? object.paymethod : 'ACH'
      end

      @content_xml.merge!(billingtype: 'balanceforward', status: 'active', contactinfo: { contact: contact })

      if ach_complete
        @content_xml[:paymentnotify]        = 'true'
        @content_xml[:achenabled]           = 'true'
        @content_xml[:achbankroutingnumber] = object.ach_routing_number.to_i
        @content_xml[:achaccountnumber]     = object.ach_account_number.to_i
        @content_xml[:achaccounttype]       = object.ach_account_type
        @content_xml[:achremittancetype]    = object.ach_remittance_type
      end

      @content_xml
    end

    private

    def validate_fields!(action)
      object_id_present = (object.respond_to?(:intacct_object_id) && object.intacct_object_id.present?) ||
                          (object.respond_to?(:id) && object.id.present?)
      unless object_id_present
        raise Intacct::Error.new(message: "Vendor requires id or intacct_object_id for #{action}")
      end

      required = case action
                 when :create
                   Intacct.intacct_vendor_create_required_fields ||
                     Intacct.intacct_vendor_required_fields
                 when :update
                   Intacct.intacct_vendor_update_required_fields ||
                     Intacct.intacct_vendor_create_required_fields ||
                     Intacct.intacct_vendor_required_fields
                 end
      required.each do |field|
        unless object.respond_to?(field) && object.send(field).present?
          raise Intacct::Error.new(message: "Vendor##{field} is required for #{action} but blank or missing")
        end
      end
      validate_billing_address!(action) if required.include?(:billing_address)
      validate_ach!(action)
    end

    def validate_ach!(_action)
      return unless object.respond_to?(:ach_routing_number) && object.ach_routing_number.present?

      %i[ach_account_number ach_account_type ach_remittance_type].each do |field|
        return unless object.respond_to?(field) && object.send(field).present?
      end
    end

    def validate_billing_address!(action)
      addr = object.billing_address
      Intacct.intacct_vendor_billing_address_required_fields.each do |sub|
        unless addr.respond_to?(sub) && addr.send(sub).present?
          raise Intacct::Error.new(message: "Vendor#billing_address.#{sub} is required for #{action} but blank or missing")
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
