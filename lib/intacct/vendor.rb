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
            run_hook :custom_vendor_fields, xml
          }
        }
      end

      successful?
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
            run_hook :custom_vendor_fields, xml
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
        contact[:mailaddress] = {
          address1: object.billing_address.address1,
          address2: object.billing_address.address2,
          city:     object.billing_address.city,
          state:    object.billing_address.state,
          zip:      object.billing_address.zipcode
        }
      end

      @content_xml = {
        name:        object.name,
        vendtype:    'Appraiser',
        taxid:       object.tax_number,
        billingtype: 'balanceforward',
        status:      'active',
        contactinfo: { contact: contact }
      }

      if object.ach_routing_number.present?
        @content_xml[:paymethod]            = 'ACH'
        @content_xml[:paymentnotify]        = 'true'
        @content_xml[:achenabled]           = 'true'
        @content_xml[:achbankroutingnumber] = object.ach_routing_number.to_i
        @content_xml[:achaccountnumber]     = object.ach_account_number.to_i
        @content_xml[:achaccounttype]       = "#{object.ach_account_type.capitalize} Account"
        @content_xml[:achremittancetype]    = object.ach_account_classification == 'business' ? 'CCD' : 'PPD'
      end

      @content_xml
    end

    private

    def validate_fields!(action)
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
