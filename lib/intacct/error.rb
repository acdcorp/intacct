class Intacct::Error < StandardError
  attr_reader :sent_xml, :response

  def initialize(message: 'Generic instant error', sent_xml: nil, response: [])
    error_description = nil
    @sent_xml = Nokogiri::XML(sent_xml)
    response.traverse do |n|
      error_description = n.content if n.name == 'description'
    end
    @response = unless error_description.blank?
                  error_description
                else
                  response
                end
    super(message)
  end
end
