module Intacct
  class Api

    attr_reader :request_xml, :response

    def build_xml
      @request_xml = Nokogiri::XML::Builder.new do |xml|
        xml.request {

          Builder::Control.new(xml_doc: xml).to_xml

          Builder::Operation.new(xml_doc: xml).xml_block {

            Builder::Authentication.new(xml_doc: xml).to_xml

            Builder::Content.new(xml_doc: xml).xml_block {
              yield xml
            }

          }
        }
      end
    end

    def send_xml(xml)
      url = Intacct.service_url || "https://www.intacct.com/ia/xml/xmlgw.phtml"
      uri = URI(url)

      response = Net::HTTP.post_form(uri, 'xmlrequest' => xml)

      @response = Intacct::Response.new(request_xml, Nokogiri::XML(response.body))
    end

  end

  class CreateCustomer < Api
    attr_reader :intacct_object_id, :name

    def initialize(intacct_object_id:, name:)
      @intacct_object_id = intacct_object_id
      @name = name
      @response = nil
    end

    def create_customer_xml
      create_xml = build_xml do |xml|
        xml.function(controlid: '1'){
          xml.send("create_customer") {
            xml.customerid intacct_object_id
            xml.name name
            xml.comments
            xml.status "active"
          }
        }
      end
      send_xml(create_xml.doc.root.to_xml)
    end
  end

  class GetCustomer < Api
    CUSTOMER_FIELDS = [
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
    ]
    attr_reader :intacct_key, :fields

    def initialize(intacct_key: nil, fields: CUSTOMER_FIELDS)
      @intacct_key = intacct_key
      @fields = fields
    end

    def perform
      get_xml = build_xml do |xml|
        xml.function(controlid: "f4") {
          xml.get(object: "customer", key: "#{intacct_key}") {
            xml.fields {
              fields.each do |field|
                xml.field field.to_s
              end
            }
          }
        }
      end
      send_xml(get_xml.doc.root.to_xml)
    end

  end

  module Builder
    class Control
      attr_reader :xml_doc

      def initialize(xml_doc: )
        @xml_doc = xml_doc
      end

      def to_xml
        xml_doc.control {
          xml_doc.senderid Intacct.xml_sender_id
          xml_doc.password Intacct.xml_password
          xml_doc.controlid "INVOICE XML"
          # Intacct.unique_id
          # Intacct.control_id
          # Intacct.version
          xml_doc.uniqueid "false"
          xml_doc.dtdversion "2.1"
        }
      end
    end

    class Authentication
      attr_reader :xml_doc

      def initialize(xml_doc:)
        @xml_doc = xml_doc
      end

      def to_xml
        xml_doc.authentication {
          xml_doc.login {
            xml_doc.userid Intacct.app_user_id
            xml_doc.companyid Intacct.app_company_id
            xml_doc.password Intacct.app_password
          }
        }
      end
    end

    class Operation
      attr_reader :xml_doc, :transaction

      def initialize(xml_doc:, transaction: false)
        @xml_doc = xml_doc
        @transaction = transaction
      end

      def xml_block

        xml_doc.operation(transaction: transaction) {
          yield xml_doc
        }
      end
    end

    class Content
      attr_reader :xml_doc

      def initialize(xml_doc:)
        @xml_doc = xml_doc
      end

      def xml_block
        xml_doc.content {
          yield xml_doc
        }
      end
    end
  end
end
