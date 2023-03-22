module Intacct
  class Vendor < Base
    def create
      send_xml('create') do |xml|
        xml.function(controlid: "1") {
          xml.create_vendor {
            xml.vendorid intacct_object_id
            vendor_xml xml
          }
        }
      end

      successful?
    end

    def update updated_vendor = false
      @object = updated_vendor if updated_vendor
      return false if object.intacct_system_id.nil?


      send_xml('update') do |xml|
        xml.function(controlid: "1") {
          xml.update_vendor(vendorid: intacct_system_id) {
            vendor_xml xml
          }
        }
      end

      successful?
    end

    def delete
      return false if object.intacct_system_id.nil?

      @response = send_xml('delete') do |xml|
        xml.function(controlid: "1") {
          xml.delete_vendor(vendorid: intacct_system_id)
        }
      end

      successful?
    end

    def intacct_object_id
      "#{intacct_vendor_prefix}#{object.legacy.legacy_id}"
    end

    def vendor_xml xml
      xml.name object.carrier.name
      #[todo] - Custom
      xml.vendtype "Appraiser"
      xml.taxid object.tax
      xml.paymethod "ACH" if object.routing_number.present?
      xml.billingtype "balanceforward"
      xml.status "active"
      xml.contactinfo {
        xml.contact {
          xml.contactname "#{object.last_name}, #{object.first_name} (#{object.id})"
          xml.printas object.full_name
          xml.companyname object.carrier.name
          xml.firstname object.first_name
          xml.lastname object.last_name
          xml.phone1 object.business_phone
          xml.cellphone object.cell_phone
          xml.email1 object.email
          if object.billing_address.present?
            xml.mailaddress {
              xml.address1 object.billing_address.line_1
              xml.address2 object.billing_address.line_2
              xml.city object.billing_address.city
              xml.state object.billing_address.state
              xml.zip object.billing_address.zipcode
            }
          end
        }
      }
      if object.routing_number.present?
        xml.paymentnotify "true"
        xml.achenabled "#{object.routing_number.present? ? "true" : "false"}"
        xml.achbankroutingnumber object.routing_number
        xml.achaccountnumber object.account_number
        xml.achaccounttype "#{object.account_type.capitalize+" Account"}"
        xml.achremittancetype "#{(object.account_classification=="business" ? "CCD" : "PPD")}"
      end
    end
  end
end
