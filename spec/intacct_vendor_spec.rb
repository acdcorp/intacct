require 'spec_helper'

describe Intacct::Vendor do
  include Helpers

  before { default_setup }

  # Builds XML through build_content_xml + hook without hitting the Intacct API.
  def build_xml(v)
    v.send(:content_xml) unless v.instance_variable_get(:@content_xml) ||
                                 v.instance_variable_get(:@content_xml_block)
    Nokogiri::XML::Builder.new do |xml|
      xml.create_vendor {
        xml.vendorid v.intacct_object_id
        v.send(:build_content_xml, xml)
        v.run_hook :custom_vendor_fields, xml
      }
    end.doc.root
  end

  # ─── Intacct::Vendor.prefix ─────────────────────────────────────────────────

  describe '.prefix' do
    it 'returns the configured vendor_prefix' do
      expect(Intacct::Vendor.prefix).to eq 'A'
    end

    it 'allows client domain model to build intacct_object_id without coupling to Intacct internals' do
      # Simulates what a client model's intacct_object_id method would do:
      #   def intacct_object_id = "#{Intacct::Vendor.prefix}#{id}"
      vendor.intacct_object_id = "#{Intacct::Vendor.prefix}#{vendor.id}"
      expect(Intacct::Vendor.new(vendor).intacct_object_id).to eq "A#{vendor.id}"
    end
  end

  # ─── intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to vendor_prefix + id' do
      expect(Intacct::Vendor.new(vendor).intacct_object_id).to eq "A#{vendor.id}"
    end

    it 'uses intacct_object_id from the object when present' do
      vendor.intacct_object_id = 'OVERRIDE-99'
      expect(Intacct::Vendor.new(vendor).intacct_object_id).to eq 'OVERRIDE-99'
    end
  end

  # ─── content_xml (hash path) ────────────────────────────────────────────────

  describe '#content_xml without block' do
    subject(:h) { Intacct::Vendor.new(vendor).content_xml }

    it 'returns a Hash' do
      expect(h).to be_a(Hash)
    end

    it 'includes top-level vendor fields' do
      expect(h[:name]).to eq vendor.name
      expect(h[:vendtype]).to eq 'Appraiser'
      expect(h[:billingtype]).to eq 'balanceforward'
      expect(h[:status]).to eq 'active'
    end

    it 'nests contact fields under contactinfo > contact' do
      contact = h.dig(:contactinfo, :contact)
      expect(contact[:contactname]).to eq vendor.contactname
      expect(contact[:email1]).to eq vendor.email
      expect(contact[:firstname]).to eq vendor.first_name
      expect(contact[:lastname]).to eq vendor.last_name
    end

    it 'includes mailaddress under contact when billing_address is present' do
      addr = h.dig(:contactinfo, :contact, :mailaddress)
      expect(addr[:address1]).to eq vendor.billing_address.address1
      expect(addr[:city]).to eq vendor.billing_address.city
      expect(addr[:zip]).to eq vendor.billing_address.zipcode
    end

    it 'omits mailaddress when billing_address is absent' do
      vendor.billing_address = nil
      contact = Intacct::Vendor.new(vendor).content_xml.dig(:contactinfo, :contact)
      expect(contact).not_to have_key(:mailaddress)
    end

    it 'omits address2 key from mailaddress when address2 is blank' do
      vendor.billing_address.address2 = ''
      mailaddr = Intacct::Vendor.new(vendor).content_xml.dig(:contactinfo, :contact, :mailaddress)
      expect(mailaddr).not_to have_key(:address2)
    end

    it 'includes address2 key in mailaddress when address2 is present' do
      vendor.billing_address.address2 = 'Suite 100'
      mailaddr = Intacct::Vendor.new(vendor).content_xml.dig(:contactinfo, :contact, :mailaddress)
      expect(mailaddr[:address2]).to eq 'Suite 100'
    end

    context 'contactinfo / contact nesting' do
      it 'nests contact one level inside contactinfo' do
        expect(h[:contactinfo]).to be_a(Hash)
        expect(h[:contactinfo][:contact]).to be_a(Hash)
        expect(h.dig(:contactinfo, :contact, :contactname)).to eq vendor.contactname
      end

      it 'does not place contact fields directly under contactinfo' do
        expect(h[:contactinfo]).not_to have_key(:contactname)
        expect(h[:contactinfo]).not_to have_key(:email1)
      end
    end

    context 'with ACH routing number present' do
      it 'defaults paymethod to ACH when object does not define it' do
        expect(h[:paymethod]).to eq 'ACH'
      end

      it 'uses object.paymethod when the object defines it' do
        vendor.paymethod = 'Check'
        expect(Intacct::Vendor.new(vendor).content_xml[:paymethod]).to eq 'Check'
      end

      it 'falls back to ACH when object.paymethod is blank' do
        vendor.paymethod = nil
        expect(Intacct::Vendor.new(vendor).content_xml[:paymethod]).to eq 'ACH'
      end

      it 'includes paymentnotify, achenabled' do
        expect(h[:paymentnotify]).to eq 'true'
        expect(h[:achenabled]).to eq 'true'
      end

      it 'reads routing and account numbers as-is from the object' do
        expect(h[:achbankroutingnumber]).to eq vendor.ach_routing_number
        expect(h[:achaccountnumber]).to eq vendor.ach_account_number
      end

      it 'reads ach_account_type from the object as-is' do
        expect(h[:achaccounttype]).to eq vendor.ach_account_type
      end

      it 'reads ach_remittance_type from the object as-is' do
        expect(h[:achremittancetype]).to eq vendor.ach_remittance_type
      end
    end

    context 'when ach_routing_number is nil' do
      before { vendor.ach_routing_number = nil }

      it 'still includes ACH fields (nil → empty tag)' do
        xml = Intacct::Vendor.new(vendor).content_xml
        expect(xml).to have_key(:achbankroutingnumber)
        expect(xml[:achbankroutingnumber]).to be_nil
      end
    end

    it 'stores the result in @content_xml' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml
      expect(v.instance_variable_get(:@content_xml)).to be_a(Hash)
    end
  end

  # ─── content_xml (block path) ───────────────────────────────────────────────

  describe '#content_xml with block' do
    it 'returns self for chaining' do
      v = Intacct::Vendor.new(vendor)
      result = v.content_xml { |xml| xml.name 'X' }
      expect(result).to be v
    end

    it 'stores the block in @content_xml_block' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'X' }
      expect(v.instance_variable_get(:@content_xml_block)).to be_a(Proc)
    end

    it 'does not set @content_xml' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'X' }
      expect(v.instance_variable_get(:@content_xml)).to be_nil
    end
  end

  # ─── XML output — hash path ──────────────────────────────────────────────────

  describe 'XML output via hash_to_xml (default path)' do
    let(:root) { build_xml(Intacct::Vendor.new(vendor)) }

    it 'renders vendorid, name, vendtype, billingtype, status' do
      expect(root.at('vendorid').text).to eq "A#{vendor.id}"
      expect(root.at('name').text).to eq vendor.name
      expect(root.at('vendtype').text).to eq 'Appraiser'
      expect(root.at('billingtype').text).to eq 'balanceforward'
      expect(root.at('status').text).to eq 'active'
    end

    it 'renders contactinfo > contact two-level structure' do
      expect(root.at('contactinfo > contact > contactname').text).to eq vendor.contactname
      expect(root.at('contactinfo > contact > email1').text).to eq vendor.email
      # fields must not leak directly onto contactinfo
      expect(root.at('contactinfo > contactname')).to be_nil
    end

    it 'renders mailaddress nested inside contact' do
      expect(root.at('contactinfo > contact > mailaddress > city').text).to eq vendor.billing_address.city
    end

    it 'renders ACH block with values taken directly from the object' do
      expect(root.at('paymethod').text).to eq 'ACH'
      expect(root.at('achaccounttype').text).to eq vendor.ach_account_type
      expect(root.at('achremittancetype').text).to eq vendor.ach_remittance_type
    end

    it 'renders paymethod before contactinfo (DTD order)' do
      names = root.children.select(&:element?).map(&:name)
      expect(names.index('paymethod')).to be < names.index('contactinfo')
    end

    it 'reflects top-level hash mutations' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml[:vendtype] = 'Inspector'
      expect(build_xml(v).at('vendtype').text).to eq 'Inspector'
    end

    it 'reflects nested hash mutations' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml.dig(:contactinfo, :contact)[:email1] = 'changed@example.com'
      expect(build_xml(v).at('email1').text).to eq 'changed@example.com'
    end
  end

  # ─── XML output — block path ─────────────────────────────────────────────────

  describe 'XML output via custom block' do
    it 'renders only what the block produces' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml do |xml|
        xml.name 'Block Name'
        xml.vendtype 'Block Type'
        xml.contactinfo { xml.contact { xml.contactname 'Block Contact' } }
      end
      root = build_xml(v)
      expect(root.at('name').text).to eq 'Block Name'
      expect(root.at('vendtype').text).to eq 'Block Type'
      expect(root.at('contactinfo > contact > contactname').text).to eq 'Block Contact'
      expect(root.at('billingtype')).to be_nil
      expect(root.at('paymethod')).to be_nil
    end
  end

  # ─── custom_vendor_fields hook ───────────────────────────────────────────────

  describe 'custom_vendor_fields hook' do
    it 'appends nodes after the default body' do
      v = Intacct::Vendor.new(vendor)
      v.custom_vendor_fields { |xml| xml.extra 'bonus' }
      root = build_xml(v)
      expect(root.at('name').text).to eq vendor.name
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'appends nodes after a custom block body' do
      v = Intacct::Vendor.new(vendor)
      v.content_xml { |xml| xml.name 'Block' }
      v.custom_vendor_fields { |xml| xml.extra 'bonus' }
      root = build_xml(v)
      expect(root.at('name').text).to eq 'Block'
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'produces no extra nodes when no hook is registered' do
      expect(build_xml(Intacct::Vendor.new(vendor)).at('extra')).to be_nil
    end
  end

  # ─── validate_fields! ────────────────────────────────────────────────────────

  describe '#validate_fields!' do
    context 'intacct_object_id — always-on check' do
      it 'passes when object has id (prefix + id fallback)' do
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'passes when object defines intacct_object_id directly (no id needed)' do
        vendor.id = nil
        vendor.intacct_object_id = 'EXPLICIT-99'
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'raises when neither id nor intacct_object_id resolves to a value' do
        vendor.id = nil
        vendor.intacct_object_id = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /requires id or intacct_object_id/)
      end
    end

    context 'gem default [:name]' do
      it 'passes when name is present' do
        v = Intacct::Vendor.new(vendor)
        expect { v.send(:validate_fields!, :create) }.not_to raise_error
        expect { v.send(:validate_fields!, :update) }.not_to raise_error
      end

      it 'raises Intacct::Error when name is blank on create' do
        vendor.name = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Vendor#name is required for create/)
      end

      it 'raises Intacct::Error when name is blank on update' do
        vendor.name = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Vendor#name is required for update/)
      end
    end

    context 'intacct_vendor_required_fields overridden globally' do
      before { Intacct.intacct_vendor_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_required_fields = [:id, :name] }

      it 'applies the override to both create and update' do
        vendor.email = nil
        v = Intacct::Vendor.new(vendor)
        expect { v.send(:validate_fields!, :create) }.to raise_error(Intacct::Error, /email/)
        expect { v.send(:validate_fields!, :update) }.to raise_error(Intacct::Error, /email/)
      end
    end

    context 'only intacct_vendor_create_required_fields set' do
      before { Intacct.intacct_vendor_create_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_create_required_fields = nil }

      it 'validates email on create' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'also applies to update when intacct_vendor_update_required_fields is not set' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end
    end

    context 'both create and update required fields set' do
      before do
        Intacct.intacct_vendor_create_required_fields = [:id, :name, :email]
        Intacct.intacct_vendor_update_required_fields = [:id, :name]
      end
      after do
        Intacct.intacct_vendor_create_required_fields = nil
        Intacct.intacct_vendor_update_required_fields = nil
      end

      it 'uses create fields for create' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'uses update fields for update — email not required' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .not_to raise_error
      end
    end

    context 'only intacct_vendor_update_required_fields set' do
      before { Intacct.intacct_vendor_update_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_vendor_update_required_fields = nil }

      it 'uses update fields for update' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'falls back to gem default for create — email not required' do
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .not_to raise_error
      end
    end

    context 'billing_address as a required field' do
      before { Intacct.intacct_vendor_create_required_fields = [:name, :billing_address] }
      after  do
        Intacct.intacct_vendor_create_required_fields = nil
        Intacct.intacct_vendor_billing_address_required_fields = nil
      end

      it 'passes when billing_address is present with all default sub-fields' do
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'raises when billing_address object is missing entirely' do
        vendor.billing_address = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Vendor#billing_address is required for create/)
      end

      it 'raises when address1 is blank (default sub-fields)' do
        vendor.billing_address.address1 = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /billing_address\.address1 is required for create/)
      end

      it 'does not raise when address2 is blank (not in default sub-fields)' do
        vendor.billing_address.address2 = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      context 'with address2 added to billing_address_required_fields' do
        before do
          Intacct.intacct_vendor_billing_address_required_fields = %i[address1 address2 city state zipcode]
        end

        it 'raises when address2 is blank' do
          vendor.billing_address.address2 = nil
          expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
            .to raise_error(Intacct::Error, /billing_address\.address2 is required for create/)
        end

        it 'passes when all sub-fields including address2 are present' do
          vendor.billing_address.address2 = 'Suite 100'
          expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
        end
      end
    end

    context 'ACH fields — no gem-level validation' do
      it 'does not raise when any ACH field is nil' do
        vendor.ach_routing_number  = nil
        vendor.ach_account_number  = nil
        vendor.ach_account_type    = nil
        vendor.ach_remittance_type = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'still includes ACH fields in content_xml even when all are nil' do
        vendor.ach_routing_number  = nil
        vendor.ach_account_number  = nil
        expect(Intacct::Vendor.new(vendor).content_xml).to have_key(:achbankroutingnumber)
      end
    end

    context 'ach_routing_number as a required field (correct way to require ACH)' do
      before { Intacct.intacct_vendor_create_required_fields = [:id, :name, :ach_routing_number] }
      after  { Intacct.intacct_vendor_create_required_fields = nil }

      it 'passes when ach_routing_number is present' do
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'raises when ach_routing_number is blank' do
        vendor.ach_routing_number = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Vendor#ach_routing_number is required for create/)
      end
    end

    context 'object method names vs XML node names' do
      it 'validates full_name (object method), not printas (XML node name)' do
        Intacct.intacct_vendor_create_required_fields = [:id, :name, :full_name]
        vendor.full_name = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /full_name/)
      ensure
        Intacct.intacct_vendor_create_required_fields = nil
      end

      it 'validates email (object method), not email1 (XML node name)' do
        Intacct.intacct_vendor_create_required_fields = [:id, :name, :email]
        vendor.email = nil
        expect { Intacct::Vendor.new(vendor).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      ensure
        Intacct.intacct_vendor_create_required_fields = nil
      end
    end
  end

  # ─── before_send_xml / after_response hooks ──────────────────────────────────

  describe 'before_send_xml and after_response hooks' do
    def stub_http(status: '200', body: nil)
      body ||= <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>success</status></result></operation>
        </response>
      XML
      fake_response = instance_double(Net::HTTPResponse, code: status, body: body)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(fake_response)
    end

    def error_body
      <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>failure</status>
            <errormessage><error><description>Something went wrong</description></error></errormessage>
          </result></operation>
        </response>
      XML
    end

    it 'fires before_send_xml with the outgoing XML string before the HTTP call' do
      stub_http
      captured = nil
      v = Intacct::Vendor.new(vendor)
      v.before_send_xml { |xml_str| captured = xml_str }
      v.create
      expect(captured).to be_a(String)
      expect(captured).to include('<create_vendor>')
    end

    it 'fires after_response with the Intacct instance on success' do
      stub_http
      captured = nil
      v = Intacct::Vendor.new(vendor)
      v.after_response { |intacct| captured = intacct }
      v.create
      expect(captured).to be v
      expect(captured.successful?).to be true
      expect(captured.intacct_action).to eq 'create'
      expect(captured.sent_xml).to include('<create_vendor>')
      expect(captured.response).to be_a(Nokogiri::XML::Document)
    end

    it 'fires after_response with the Intacct instance on error (fires regardless of outcome)' do
      stub_http(status: '200', body: error_body)
      captured = nil
      v = Intacct::Vendor.new(vendor)
      v.after_response { |intacct| captured = intacct }
      v.create
      expect(captured).to be v
      expect(captured.successful?).to be false
      expect(captured.class.name).to eq 'Intacct::Vendor'
    end

    it 'fires before_send_xml before the HTTP request is made' do
      call_order = []
      fake_response = instance_double(Net::HTTPResponse, code: '200', body: <<~XML)
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>success</status></result></operation>
        </response>
      XML
      allow_any_instance_of(Net::HTTP).to receive(:request) do
        call_order << :http
        fake_response
      end
      v = Intacct::Vendor.new(vendor)
      v.before_send_xml { call_order << :hook }
      v.create
      expect(call_order).to eq [:hook, :http]
    end

    it 'fires after_response before on_error when the call fails' do
      stub_http(status: '200', body: error_body)
      call_order = []
      v = Intacct::Vendor.new(vendor)
      v.after_response { call_order << :after_response }
      v.on_error { call_order << :on_error }
      v.create
      expect(call_order).to eq [:after_response, :on_error]
    end

    it 'exposes class name so the client knows which Intacct type fired' do
      stub_http
      captured_class = nil
      v = Intacct::Vendor.new(vendor)
      v.after_response { |intacct| captured_class = intacct.class.name }
      v.create
      expect(captured_class).to eq 'Intacct::Vendor'
    end
  end

  # ─── #create duplicate fallback ─────────────────────────────────────────────

  describe '#create duplicate fallback' do
    subject { Intacct::Vendor.new(vendor) }

    before { vendor.intacct_created_at = nil }

    def stub_requests(*bodies)
      responses = bodies.map { |b| instance_double(Net::HTTPResponse, code: '200', body: b) }
      call_idx = [0]
      allow_any_instance_of(Net::HTTP).to receive(:request) do
        resp = responses[call_idx[0]] || responses.last
        call_idx[0] += 1
        resp
      end
    end

    def duplicate_xml
      <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>failure</status>
            <errormessage><error><errorno>BL03002185</errorno></error></errormessage>
          </result></operation>
        </response>
      XML
    end

    it 'returns true and fires after_create with self' do
      stub_requests(duplicate_xml)
      captured = nil
      subject.after_create { |i| captured = i }
      result = subject.create
      expect(result).to be true
      expect(captured).to be subject
    end

    it 'sets intacct_system_id on the domain object' do
      stub_requests(duplicate_xml)
      subject.create
      expect(vendor.intacct_system_id).to be_present
    end

    it 'sets intacct_created_at on the domain object' do
      stub_requests(duplicate_xml)
      subject.create
      expect(vendor.intacct_created_at).to be_present
    end

    def bl34_duplicate_xml
      <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>failure</status>
            <errormessage><error><errorno>BL34000061</errorno></error></errormessage>
          </result></operation>
        </response>
      XML
    end

    it 'returns true when BL34000061 fires (contact already exists)' do
      stub_requests(bl34_duplicate_xml)
      expect(subject.create).to be true
    end

    it 'sets intacct_system_id when BL34000061 fires' do
      stub_requests(bl34_duplicate_xml)
      subject.create
      expect(vendor.intacct_system_id).to be_present
    end

    it 'fires after_create with self when BL34000061 fires' do
      stub_requests(bl34_duplicate_xml)
      captured = nil
      subject.after_create { |i| captured = i }
      subject.create
      expect(captured).to be subject
    end
  end
end
