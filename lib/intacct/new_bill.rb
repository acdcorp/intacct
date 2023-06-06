module Intacct
  class NewBill < NewBase
    BILL_FIELDS = {
      billno: nil,
      ponumber: nil,
      description: nil,
      externalid: nil,
      basecurr: nil,
      currency: nil,
      exchratetype: nil,
      datecreated: { year: nil, month: nil, day: nil },
      dateposted: { year: nil, month: nil, day: nil },
      datedue: { year: nil, month: nil, day: nil },
      vendor_key: nil,
      customer_key: nil,
      customer: nil,
      vendor: nil,
      custom_fields: [],
      bill_items: {
        base_amount_with_sales_tax: nil,
        mileage_amount_with_sales_tax: nil,
        travel_amount_with_sales_tax: nil,
        additional_amount_with_sales_tax: nil,
        standard_amount: nil,
        line_items: [
          {
            gl_account_no: nil,
            amount: nil,
            memo: nil,
            location_id: nil,
            item_1099: nil,
            customer_key: nil,
            vendor_key:  nil,
            employee_id: nil,
            class_id: nil
          }
        ]
      }
    }
    attr_reader :billno, :ponumber,
      :description, :externalid,
      :basecurr, :currency,
      :exchratetype, :datecreated,
      :dateposted, :datedue,
      :vendor_key, :customer_key,
      :customer, :vendor,
      :custom_fields, :bill_items,
      :line_items

    def initialize(bill={})
      BILL_FIELDS.keys.each do |field|
        bill.fetch(field)
      end

      BILL_FIELDS[:datecreated].keys.each do |field|
        bill.fetch(:datecreated).fetch(field)
      end

      BILL_FIELDS[:dateposted].keys.each do |field|
        bill.fetch(:dateposted).fetch(field)
      end

      BILL_FIELDS[:datedue].keys.each do |field|
        bill.fetch(:datedue).fetch(field)
      end

      BILL_FIELDS[:bill_items].keys.each do |field|
        bill.fetch(:bill_items).fetch(field)
      end

      bill.fetch(:bill_items, {}).fetch(:line_items).to_a
      bill.fetch(:bill_items, {}).fetch(:line_items).fetch(0)

      @line_items = []

      BILL_FIELDS[:bill_items][:line_items][0].keys.each do |field|
        bill.fetch(:bill_items, {}).fetch(:line_items).each do |line_item|
          line_item.fetch(field)
        end
      end

      bill.dig(:bill_items, :line_items).each do |line_item|
        add_line_item(line_item)
      end

      @custom_fields = []
      bill.fetch(:custom_fields, []).each do |custom_field|
        add_custom_field(name: custom_field.fetch(:name), value: custom_field(:value))
      end

      @bill = bill
    end

    def add_custom_field(name:, value:)
      field = { name: name, value: value}
      custom_fields << field
    end

    def add_line_item(line_item)
      bill_line_item = bill.line_item
      bill_line_item.glaccountno = line_item.fetch(:gl_account_no)
      bill_line_item.amount = line_item.fetch(:amount)
      bill_line_item.memo = line_item.fetch(:memo)
      bill_line_item.locationid = line_item.fetch(:location_id)
      bill_line_item.item1099 = line_item.fetch(:item_1099)
      bill_line_item.customerid = line_item.fetch(:customer_key)
      bill_line_item.vendorid = line_item.fetch(:vendor_key)
      bill_line_item.employeeid = line_item.fetch(:employee_key)
      bill_line_item.classid = 'A100'
      line_items << bill_line_item.to_h
    end

    def self.post(bill)
      intacct_bill = new(bill: bill)

      intacct_customer = if bill.customer_key?
        Intacct::NewCustomer.get(bill.customer_key)
      else
        Intacct::NewCustomer.create(bill.customer)
      end

      intacct_vendor = if bill.vendor_key?
        Intacct::NewVendor.get(bill.vendor_key)
      else
        Intacct::NewVendor.create(bill.vendor)
      end

      intacct_api_bill = IntacctApi::CreateBill.new(bill: bill)
      intacct_api_bill.build_xml

      intacct_bill.send_xml

      intacct_bill
    end

    def self.get(intacct_key)
    end
  end
end
