require 'securerandom'

module Intacct
  # Intacct::Base is the foundation for all Intacct domain classes
  # (Vendor, Customer, Invoice, Bill). It handles XML building, HTTP
  # transport, and a hook system that lets client applications react to
  # every stage of the lifecycle without monkey-patching this class.
  #
  # ─── Available hooks ──────────────────────────────────────────────────────────
  #
  # Hook                Fires when                  Arguments
  # ──────────────────  ──────────────────────────  ────────────────────────────
  # before_create       before a create is sent     (none)
  # after_create        after a successful create   intacct_instance (self)
  # after_update        after a successful update   intacct_instance (self)
  # after_delete        after a successful delete   intacct_instance (self)
  # after_get           after a successful get      (none)
  # after_get_list      after a successful get_list (none)
  # before_send_xml     before the HTTP call        xml_string
  # after_send_xml      after a successful call     intacct_action (String)
  # after_response      after any HTTP call         intacct_instance (self)
  # on_error            after a failed call         (none)
  #
  # ─── after_response — preferred hook for logging ─────────────────────────────
  #
  # `after_response` fires regardless of success or failure and passes the
  # Intacct instance as its argument.  The instance exposes:
  #
  #   intacct.intacct_action  # => "create", "update", "delete", "get"
  #   intacct.sent_xml        # => the outgoing XML string
  #   intacct.response        # => Nokogiri::XML::Document of the API response
  #   intacct.successful?     # => true / false
  #   intacct.class.name      # => "Intacct::Vendor", "Intacct::Invoice", etc.
  #   intacct.object          # => the domain object passed to new()
  #
  # Example — logging every outbound call to a database table:
  #
  #   vendor = Intacct::Vendor.new(my_vendor)
  #   vendor.after_response do |intacct|
  #     record = intacct.object.is_a?(ActiveRecord::Base) ? intacct.object
  #                                                       : intacct.object.vendor
  #     MyIntacctLog.create!(
  #       direction:   :outbound,
  #       action:      intacct.intacct_action,
  #       params:      intacct.sent_xml,
  #       response:    intacct.response.to_s,
  #       success:     intacct.successful?,
  #       record_type: record&.class&.name,
  #       record_id:   record&.id
  #     )
  #   end
  #   vendor.create
  #
  # ─── Recommended: class-level hooks in an initializer ───────────────────────
  #
  # Register hooks once per class. They fire for every instance, including
  # those spawned internally (e.g. the Vendor/Customer creates inside
  # Invoice#create and Bill#create).
  #
  # By the time after_create/update/delete fires, the gem has already written
  # all Intacct values back onto the in-memory object:
  #   - intacct_system_id  (set by set_intacct_system_id)
  #   - intacct_key        (set directly from the API response)
  #   - intacct_created_at / intacct_updated_at / intacct_deleted_at
  #     (set by set_date_time via after_send_xml, which fires first)
  # Your hook just needs to persist:
  #
  #   # config/initializers/intacct.rb
  #   Intacct::Vendor.after_create   { |i| i.object.save! }
  #   Intacct::Vendor.after_update   { |i| i.object.save! }
  #   Intacct::Vendor.after_delete   { |i| i.object.save! }
  #
  #   Intacct::Customer.after_create { |i| i.object.save! }
  #   Intacct::Customer.after_update { |i| i.object.save! }
  #   Intacct::Customer.after_delete { |i| i.object.save! }
  #
  #   Intacct::Invoice.after_create  { |i| i.object.invoice.save! }
  #   Intacct::Invoice.after_update  { |i| i.object.invoice.save! }
  #   Intacct::Invoice.after_delete  { |i| i.object.invoice.save! }
  #
  #   Intacct::Bill.after_create     { |i| i.object.payment.save! }
  #   Intacct::Bill.after_update     { |i| i.object.payment.save! }
  #   Intacct::Bill.after_delete     { |i| i.object.payment.save! }
  #
  #   # Log every outbound call regardless of outcome:
  #   [Intacct::Vendor, Intacct::Customer, Intacct::Invoice, Intacct::Bill].each do |klass|
  #     klass.after_response { |i| MyIntacctLog.create!(sent_xml: i.sent_xml, ...) }
  #   end
  # ─────────────────────────────────────────────────────────────────────────────
  class Base < Struct.new(:object, :current_user)
    include Hooks
    include Hooks::InstanceHooks

    define_hook :after_create, :after_update, :after_delete,
      :after_get, :after_get_list, :after_send_xml, :on_error, :before_create,
      :before_send_xml, :after_response

    after_create :set_intacct_system_id
    after_delete :delete_intacct_system_id
    after_delete :delete_intacct_key
    after_send_xml :set_date_time

    attr_accessor :response, :data, :sent_xml, :intacct_action

    def initialize *params
      params[0] = OpenStruct.new(params[0]) if params[0].is_a? Hash
      super(*params)
    end

    def record_error?
      @record_error
    end

    def default_control_id
      "#{self.class.name.split('::').last.upcase}-#{SecureRandom.hex(6)}"
    end

    def successful?
      if status = response.at('//result//status') and status.content == "success"
        true
      else
        false
      end
    end

    private

    def send_xml action
      @intacct_action = action.to_s
      run_hook :"before_#{intacct_action}" if action=="create"

      builder = Nokogiri::XML::Builder.new do |xml|
        xml.request {
          xml.control {
            xml.senderid Intacct.xml_sender_id
            xml.password Intacct.xml_password
            xml.controlid default_control_id
            xml.uniqueid Intacct.uniq_id
            xml.dtdversion Intacct.dtdversion
          }
          xml.operation(transaction: "false") {
            xml.authentication {
              xml.login {
                xml.userid Intacct.app_user_id
                xml.companyid Intacct.app_company_id
                xml.password Intacct.app_password
              }
            }
            xml.content {
              yield xml
            }
          }
        }
      end

      xml = builder.doc.root.to_xml
      @sent_xml = xml

      run_hook :before_send_xml, xml

      url = Intacct.service_url || "https://www.intacct.com/ia/xml/xmlgw.phtml"
      uri = URI(url)

      Intacct.logger.debug { "[Intacct] POST #{url} action=#{intacct_action}" }
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = Intacct.http_open_timeout || 5
      http.read_timeout  = Intacct.http_read_timeout  || 30
      request = Net::HTTP::Post.new(uri)
      request.set_form_data('xmlrequest' => xml)
      res = http.request(request)
      @response = Nokogiri::XML(res.body)

      # Fires for every response — success or failure. Passes self so the
      # client has access to intacct_action, sent_xml, response, successful?,
      # class.name, and object. Use this hook to log all outbound calls.
      run_hook :after_response, self

      if successful?
        if key = response.at('//result/key')
          set_intacct_key key.content
        end

        if intacct_action
          run_hook :after_send_xml, intacct_action
          run_hook :"after_#{intacct_action}", self
        end
      else
        run_hook :on_error
      end

      @response
    end

    %w(invoice bill vendor customer).each do |type|
      define_method "intacct_#{type}_prefix" do
        Intacct.send("#{type}_prefix")
      end
    end

    def self.prefix
      Intacct.send("#{name.split('::').last.downcase}_prefix")
    end

    def intacct_system_id
      intacct_object_id
    end

    def set_intacct_system_id(_ = nil)
      object.intacct_system_id = intacct_object_id
    end

    def delete_intacct_system_id(_ = nil)
      object.intacct_system_id = nil
    end

    def set_intacct_key key
      object.intacct_key = key if object.respond_to? :intacct_key
    end

    def delete_intacct_key(_ = nil)
      object.intacct_key = nil if object.respond_to? :intacct_key
    end

    def set_date_time type
      if %w(create update delete).include? type
        if object.respond_to? :"intacct_#{type}d_at"
          object.send("intacct_#{type}d_at=", DateTime.now)
        end
        #also update updated at on create
        if type=="create" and object.respond_to?(:"intacct_updated_at")
          object.intacct_updated_at = DateTime.now
        end
      end
    end

  end
end
