require 'securerandom'

module Intacct
  class Base < Struct.new(:object, :current_user)
    include Hooks
    include Hooks::InstanceHooks

    define_hook :after_create, :after_update, :after_delete,
      :after_get, :after_get_list, :after_send_xml, :on_error, :before_create

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
      Intacct.logger.debug { "[Intacct] response status=#{res.code}" }
      @response = Nokogiri::XML(res.body)

      if successful?
        if key = response.at('//result/key')
          set_intacct_key key.content
        end

        if intacct_action
          run_hook :after_send_xml, intacct_action
          run_hook :"after_#{intacct_action}"
        end
      else
        run_hook :on_error
      end

      @response
    end

    def successful?
      if status = response.at('//result//status') and status.content == "success"
        true
      else
        false
      end
    end

    %w(invoice bill vendor customer).each do |type|
      define_method "intacct_#{type}_prefix" do
        Intacct.send("#{type}_prefix")
      end
    end

    def intacct_system_id
      intacct_object_id
    end

    def set_intacct_system_id
      object.intacct_system_id = intacct_object_id
    end

    def delete_intacct_system_id
      object.intacct_system_id = nil
    end

    def set_intacct_key key
      object.intacct_key = key if object.respond_to? :intacct_key
    end

    def delete_intacct_key
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
