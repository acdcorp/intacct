require 'ostruct'

INTACCT_URL = "https://www.intacct.com/ia/xml/xmlgw.phtml"

SUCCESS_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <response>
    <operation>
      <result>
        <status>success</status>
        <data listtype="customer" count="0"/>
      </result>
    </operation>
  </response>
XML

FAILURE_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <response>
    <operation>
      <result>
        <status>failure</status>
        <errormessage>
          <error>
            <errorno>XL03000006</errorno>
            <description>Sign-in information is incorrect. Please check your request.</description>
          </error>
        </errormessage>
      </result>
    </operation>
  </response>
XML

def stub_intacct(body)
  stub_request(:post, INTACCT_URL).to_return(status: 200, body: body)
end

def setup_credentials
  Intacct.xml_sender_id   = "sender"
  Intacct.xml_password    = "senderpass"
  Intacct.app_user_id     = "user"
  Intacct.app_company_id  = "company"
  Intacct.app_password    = "pass"
  Intacct.customer_prefix = "C"
  Intacct.invoice_prefix  = "INV-"
  Intacct.bill_prefix     = "BILL-"
end
