require './lib/intacct/intest.rb'
module Intacct
  class NewBase
    include Hooks
    include Hooks::InstanceHooks

    define_hook :after_create, :after_update, :after_delete,
      :after_get, :after_get_list, :after_send_xml, :before_create, :on_error,
      :after_initialize, :before_get

    after_delete :delete_intacct_system_id
    after_delete :delete_intacct_key

    after_send_xml :store_response
    after_send_xml :store_successful_data
    after_send_xml :store_failing_data


    attr_reader :response, :intacct_action

    attr_accessor :data, :intacct_key,
      :intacct_error, :date_time,
      :intacct_object_id, :response_intacct_key,
      :sent_xml, :responses, :intacct_api

    def initialize(intacct_api:, intacct_action:)
      @intacct_key = nil
      @intacct_api = intacct_api
      @response = nil
      @sent_xml = nil
      @response_intacct_key = '//result/key'
      @responses = []
      @intacct_action = intacct_action.freeze
      run_hook :after_initialize
    end

    def validate
      raise Intacct::Error.new(message: action_error_validation ) unless send("#{intacct_action}_valid?")
    end

    def store_response
      @responses << @response
    end

    def store_successful_data
      return false unless successful?
      if key = response.at(response_intacct_key)
        @intacct_key = key.content
        @intacct_date_time = Time.zone.now
      end
    end

    def store_failing_data
      return false if successful?
      @intacct_error = response.at('//result/errormessage/error/description')
      @intacct_error_number = response.at('//result/errorno')&.content
      @intacct_error_description2 = response.at('//result/errormessage/error/description2')
      @intacct_error_correction = response.at('//result/errormessage/error/correction')
      run_hook :on_error
    end


    def send_xml
      run_hook :"before_#{intacct_action}"
      @response = intacct_api.send_xml
      @sent_xml = @response.request_xml
      @response = @response.response_xml

      run_hook :after_send_xml
      run_hook :"after_#{intacct_action}"
    end

    def successful?
      response.at('//result//status')&.content == "success"
    end

  end
end
