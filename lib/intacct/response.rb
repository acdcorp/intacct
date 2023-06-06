module Intacct
  class Response
    attr_reader :request_xml, :response_xml

    def initialize(request_xml, response_xml)
      @request_xml = request_xml
      @response_xml = response_xml
    end
  end
end
