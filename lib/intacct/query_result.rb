module Intacct
  class QueryResult
    attr_reader :records, :data, :response, :sent_xml

    def initialize(records: nil, data: nil, response: nil, sent_xml: nil)
      @records  = records
      @data     = data
      @response = response
      @sent_xml = sent_xml
    end

    def found?
      !records.nil? || !data.nil?
    end
  end
end
