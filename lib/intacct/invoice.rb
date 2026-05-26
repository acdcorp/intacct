# frozen_string_literal: true
module Intacct
  class Invoice < Intacct::Base
    attr_accessor :customer_data
    define_hook :custom_invoice_fields

    def create
      raise Intacct::Error.new(message: 'Invoice already created on intacct') if object.invoice.intacct_system_id.present?

      validate_fields!(:create)

      # Need to create the customer if one doesn't exist
      intacct_customer = Intacct::Customer.new object.customer
      unless object.customer.intacct_system_id.present?
        intacct_customer.create
        object.customer = intacct_customer.object
        intacct_customer = Intacct::Customer.new object.customer
        @customer_data = intacct_customer.data
      end

      if @customer_data.nil? && intacct_customer.get
        object.customer = intacct_customer.object
        @customer_data = intacct_customer.data
      end

      if object.vendor && object.vendor.intacct_system_id.blank?
        intacct_vendor = Intacct::Vendor.new object.vendor
        intacct_vendor.create
        object.vendor = intacct_vendor.object
      end

      content_xml unless @content_xml || @content_xml_block

      send_xml('create') do |xml|
        xml.function(controlid: "f1") {
          xml.create_invoice {
            build_content_xml(xml)
            run_hook :custom_invoice_fields, xml, self
          }
        }
      end

      success = successful?

      return true if success

      if !success
        #this invoice already exists... lets grab it and force update
        # BL03002185 = A transaction with that number already exists
        if @response.search('//result//errorno').any? { |e| e.content == Intacct.duplicate_transaction_error_code }
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
          if intacct_invoice_list.response && (key_node = intacct_invoice_list.response.at("//invoice/key"))
            set_intacct_key key_node.content
          end
          run_hook :after_send_xml, "create"
          run_hook :after_create, self
          return true
        end
      end

      success
    end

    def delete
      return false unless object.invoice.intacct_system_id.present?

      send_xml('delete') do |xml|
        xml.function(controlid: '1') {
          xml.delete_invoice(externalkey: 'false', key: object.invoice.intacct_key)
        }
      end

      successful?
    end

    def update updated_invoice = false
      @object = updated_invoice if updated_invoice
      return false unless object.invoice.intacct_key.present?

      send_xml('update') do |xml|
        xml.function(controlid: '1') {
          xml.update_invoice(key: object.invoice.intacct_key) {
            yield xml
          }
        }
      end

      successful?
    end

    def get_list(limit = 1000, label: nil)
      @intacct_label = label
      send_xml('get_list') do |xml|
        xml.function(controlid: 'f1') {
          xml.get_list(object: 'invoice', maxitems: limit) {
            yield xml
          }
        }
      end

      self
    end

    def intacct_object_id
      object.invoice.intacct_object_id || "#{intacct_invoice_prefix}#{object.invoice.id}"
    end

    def intacct_domain_object
      object&.invoice
    end

    def content_xml(&block)
      if block
        @content_xml_block = block
        return self
      end

      termname = customer_data&.termname
      @content_xml = {
        customerid:  object.customer.intacct_system_id.present? ? object.customer.intacct_system_id : "#{intacct_customer_prefix}#{object.customer.id}",
        datecreated: {
          year:  object.invoice.created_at.strftime("%Y"),
          month: object.invoice.created_at.strftime("%m"),
          day:   object.invoice.created_at.strftime("%d")
        },
        termname:  termname.present? ? termname : "Net 30",
        invoiceno: intacct_object_id
      }
    end

    def get_employee_id
      return if !customer_data

      system = Intacct.system_name

      #make sure we have all values
      %w(commission_start_date commission_end_date employee).each do |field|
        return unless customer_data.send("#{system}_#{field}").present?
      end

      #make sure valid time
      return if Time.strptime(customer_data.send("#{system}_commission_start_date"),"%m/%d/%Y") > Time.zone.now
      return if Time.strptime(customer_data.send("#{system}_commission_end_date"),"%m/%d/%Y") < Time.zone.now

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

    private

    def validate_fields!(action)
      object_id_present = (object.invoice.respond_to?(:intacct_object_id) && object.invoice.intacct_object_id.present?) ||
                          (object.invoice.respond_to?(:id) && object.invoice.id.present?)
      unless object_id_present
        raise Intacct::Error.new(message: "Invoice requires id or intacct_object_id for #{action}")
      end

      required = case action
                 when :create
                   Intacct.intacct_invoice_create_required_fields ||
                     Intacct.intacct_invoice_required_fields
                 when :update
                   Intacct.intacct_invoice_update_required_fields ||
                     Intacct.intacct_invoice_create_required_fields ||
                     Intacct.intacct_invoice_required_fields
                 end
      required.each do |field|
        unless object.invoice.respond_to?(field) && object.invoice.send(field).present?
          raise Intacct::Error.new(message: "Invoice##{field} is required for #{action} but blank or missing")
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
