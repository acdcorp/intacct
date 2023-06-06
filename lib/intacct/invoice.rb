module Intacct
  class Invoice < Intacct::Base
    attr_accessor :customer_data
    define_hook :custom_invoice_fields

    def create
      raise Intacct::Error.new(message: 'Invoice already created on intacct') if object.invoice.intacct_system_id.present?

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

      if object.vendor and object.vendor.intacct_system_id.blank?
        intacct_vendor = Intacct::Vendor.new object.vendor
        intacct_vendor.create
        object.vendor = intacct_vendor.object
      end

      send_xml('create') do |xml|
        xml.function(controlid: "f1") {
          xml.create_invoice {
            invoice_xml xml
          }
        }
      end

      success = successful?

      return true if success

      if !success
        #this invoice already exists... lets grab it and force update
        if resp = @response.at('//result//errorno') and resp.content == "PL01000127"
          intacct_invoice_list = Intacct::Invoice.new
          intacct_invoice_list.get_list(1) do |xml|
            xml.filter {
              xml.expression {
                xml.field "invoiceno"
                xml.operator "="
                xml.value intacct_object_id
              }
            }
          end
          if intacct_invoice_list.response and invoice_key = intacct_invoice_list.response.at("//invoice/key").content
            set_intacct_key invoice_key
            run_hook :after_send_xml, "create"
            run_hook :after_create
            return true
          end
        end
      end

      success
    end

    def delete
      return false unless object.invoice.intacct_system_id.present?

      send_xml('delete') do |xml|
        xml.function(controlid: "1") {
          xml.delete_invoice(externalkey: "false", key: object.invoice.intacct_key)
        }
      end

      successful?
    end

    def update updated_invoice = false
      @object = updated_invoice if updated_invoice
      return false unless object.invoice.intacct_key.present?

      send_xml('update') do |xml|
        xml.function(controlid: "1") {
          xml.update_invoice(key: object.invoice.intacct_key) {
            yield xml
          }
        }
      end

      successful?
    end

    def get_list limit=1000

      # fields = [] if fields.empty?

      send_xml('get_list') do |xml|
        xml.function(controlid: "f1") {
          xml.get_list(object: "invoice", maxitems: limit) {
            yield xml
          }
        }
      end

      successful?
    end

    def intacct_object_id
      "#{intacct_invoice_prefix}#{object.invoice.id}"
    end

    def invoice_xml xml
      xml.customerid "#{object.customer.intacct_system_id}"
      xml.datecreated {
        xml.year object.invoice.created_at.strftime("%Y")
        xml.month object.invoice.created_at.strftime("%m")
        xml.day object.invoice.created_at.strftime("%d")
      }

      termname = customer_data.termname
      xml.termname termname.present?? termname : "Net 30"

      xml.invoiceno intacct_object_id
      run_hook :custom_invoice_fields, xml
    end

    def set_intacct_system_id
      object.invoice.intacct_system_id = intacct_object_id
    end

    def set_intacct_key key
      object.invoice.intacct_key = key
    end

    def delete_intacct_system_id
      object.invoice.intacct_system_id = nil
    end

    def delete_intacct_key
      object.invoice.intacct_key = nil
    end

    def get_employee_id
      return if !customer_data

      system = Intacct.system_name

      #make sure we have all values
      %w(commission_start_date commission_end_date employee).each do |field|
        return unless customer_data.send("#{system}_#{field}").present?
      end

      #make sure valid time
      return if Time.strptime(customer_data.send("#{system}_commission_start_date"),"%m/%d/%Y")>Time.now
      return if Time.strptime(customer_data.send("#{system}_commission_end_date"),"%m/%d/%Y")<Time.now

      customer_data.send("#{system}_employee")
    end

    def get_commission_amount
      return if !customer_data

      system = Intacct.system_name

      #make sure we have all values
      %w(commission_start_date commission_end_date employee commission_rate).each do |field|
        return unless customer_data.send("#{system}_#{field}").present?
      end

      start_date = Time.strptime(customer_data.send("#{system}_commission_start_date"),"%m/%d/%Y")
      end_date = Time.strptime(customer_data.send("#{system}_commission_end_date"),"%m/%d/%Y")+1.day

      #make sure valid time
      return if start_date>Time.now
      return if end_date<Time.now

      #need to covert from decimal to %
      if start_date>1.year.ago #if within the first year
        customer_data.send("#{system}_commission_rate").to_f*100
      else #if in second year half the commission
        (customer_data.send("#{system}_commission_rate").to_f*100)/2
      end
    end

    def set_date_time type
      if %w(create update delete).include? type
        if object.invoice.respond_to? :"intacct_#{type}d_at"
          object.invoice.send("intacct_#{type}d_at=", DateTime.now)
        end
      end
    end
  end
end
