module Intacct
  class NewVendor < NewBase

    attr_reader :vendor, :fields, :data_fields

    def initialize(vendor)
      @vendor = vendor
      super
    end

    def create_valid?
      customer.respond_to?(:create_vendor_xml)
      customer.respond_to?(:intacct_object_id)
    end

    def get_valid?
      customer.respond_to?(:get_vendor_xml)
      customer.respond_to?(:intacct_key)
    end

    def create
      @intacct_api = IntacctApi::CreateVendor.
        new(intacct_object_id: vendor.intacct_object_id)
      @sent_xml = intacct_api.build_xml do |xml|
        vendor.create_vendor_xml(xml)
      end
      send_xml('create')
    end

    def get
      @intacct_api = IntacctApi::GetVendor.
        new(intacct_key: intacct_key)
      @send_xml = intacct_api.build_xml do |xml|
        vendor.get_vendor_xml(xml)
      end
      send_xml('get')
    end

    def vendor_xml xml
      xml.name "#{vendor.company_name.present? ? vendor.company_name : vendor.full_name}"
      #[todo] - Custom
      xml.vendtype "Appraiser"
      xml.taxid vendor.tax_number
      xml.paymethod "ACH" if vendor.ach_routing_number.present?
      xml.billingtype "balanceforward"
      xml.status "active"
      xml.contactinfo {
        xml.contact {
          xml.contactname "#{vendor.last_name}, #{object.first_name} (#{object.id})"
          xml.printas vendor.full_name
          xml.companyname vendor.company_name
          xml.firstname vendor.first_name
          xml.lastname vendor.last_name
          xml.phone1 vendor.business_phone
          xml.cellphone vendor.cell_phone
          xml.email1 vendor.email
          if vendor.billing_address.present?
            xml.mailaddress {
              xml.address1 vendor.billing_address.address1
              xml.address2 vendor.billing_address.address2
              xml.city vendor.billing_address.city
              xml.state vendor.billing_address.state
              xml.zip vendor.billing_address.zipcode
            }
          end
        }
      }
      if vendor.ach_routing_number.present?
        xml.paymentnotify "true"
        xml.achenabled "#{vendor.ach_routing_number.present? ? "true" : "false"}"
        xml.achbankroutingnumber vendor.ach_routing_number.to_i
        xml.achaccountnumber vendor.ach_account_number.to_i
        xml.achaccounttype "#{vendor.ach_account_type.capitalize+" Account"}"
        xml.achremittancetype "#{(vendor.ach_account_classification=="business" ? "CCD" : "PPD")}"
      end
    end

  end

  def action_error_validation
    "Invalid Vendor data, it requires: vendor_xml, intacct_object_id and intacct_key"
  end
end
