require 'spec_helper'

describe Intacct::Invoice do
  include Helpers

  before { default_setup }

  # Invoice wraps a composite object: { invoice: invoice_obj, vendor: vendor_obj, customer: customer_obj }
  let(:composite) { OpenStruct.new(invoice: invoice, vendor: vendor, customer: customer) }
  let(:intacct_invoice) { Intacct::Invoice.new(composite) }

  def build_xml(inv)
    inv.send(:content_xml) unless inv.instance_variable_get(:@content_xml) ||
                                   inv.instance_variable_get(:@content_xml_block)
    Nokogiri::XML::Builder.new do |xml|
      xml.create_invoice {
        inv.send(:build_content_xml, xml)
        inv.run_hook :custom_invoice_fields, xml, inv
      }
    end.doc.root
  end

  # ─── Intacct::Invoice.prefix ────────────────────────────────────────────────

  describe '.prefix' do
    it 'returns the configured invoice_prefix' do
      expect(Intacct::Invoice.prefix).to eq 'AUTO-'
    end

    it 'allows client domain model to build intacct_object_id without coupling to Intacct internals' do
      invoice.intacct_object_id = "#{Intacct::Invoice.prefix}#{invoice.id}"
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end
  end

  # ─── #intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to invoice_prefix + invoice.id' do
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end

    it 'uses object.invoice.intacct_object_id when present' do
      invoice.intacct_object_id = 'EXPLICIT-INV-42'
      expect(intacct_invoice.intacct_object_id).to eq 'EXPLICIT-INV-42'
    end

    it 'falls back to prefix + id when intacct_object_id is nil' do
      invoice.intacct_object_id = nil
      expect(intacct_invoice.intacct_object_id).to eq "AUTO-#{invoice.id}"
    end
  end

  # ─── #intacct_domain_object ──────────────────────────────────────────────────

  describe '#intacct_domain_object' do
    it 'returns object.invoice' do
      expect(intacct_invoice.intacct_domain_object).to be invoice
    end

    it 'routes set_intacct_system_id to object.invoice' do
      intacct_invoice.send(:set_intacct_system_id)
      expect(invoice.intacct_system_id).to eq intacct_invoice.intacct_object_id
    end

    it 'routes set_intacct_key to object.invoice' do
      intacct_invoice.send(:set_intacct_key, 'KEY-42')
      expect(invoice.intacct_key).to eq 'KEY-42'
    end

    it 'routes delete_intacct_system_id to object.invoice' do
      invoice.intacct_system_id = 'EXISTING'
      intacct_invoice.send(:delete_intacct_system_id)
      expect(invoice.intacct_system_id).to be_nil
    end

    it 'routes set_date_time to object.invoice' do
      invoice.intacct_created_at = nil
      intacct_invoice.send(:set_date_time, 'create')
      expect(invoice.intacct_created_at).not_to be_nil
    end
  end

  # ─── content_xml (hash path) ────────────────────────────────────────────────

  describe '#content_xml without block' do
    subject(:h) do
      c = Intacct::Invoice.new(composite)
      c.customer_data = OpenStruct.new(termname: "Net 30")
      c.content_xml
    end

    it 'returns a Hash' do
      expect(h).to be_a(Hash)
    end

    it 'includes customerid' do
      expect(h[:customerid]).to eq customer.intacct_system_id
    end

    it 'includes termname' do
      expect(h[:termname]).to eq "Net 30"
    end

    it 'includes invoiceno' do
      expect(h[:invoiceno]).to eq "AUTO-#{invoice.id}"
    end

    it 'includes datecreated hash' do
      expect(h[:datecreated]).to be_a(Hash)
      expect(h[:datecreated][:year]).to eq invoice.created_at.strftime("%Y")
      expect(h[:datecreated][:month]).to eq invoice.created_at.strftime("%m")
      expect(h[:datecreated][:day]).to eq invoice.created_at.strftime("%d")
    end

    it 'stores the result in @content_xml' do
      c = Intacct::Invoice.new(composite)
      c.customer_data = OpenStruct.new(termname: "Net 30")
      c.content_xml
      expect(c.instance_variable_get(:@content_xml)).to be_a(Hash)
    end

    it 'defaults termname to Net 30 when customer_data has no termname' do
      c = Intacct::Invoice.new(composite)
      c.customer_data = OpenStruct.new(termname: nil)
      h = c.content_xml
      expect(h[:termname]).to eq "Net 30"
    end

    it 'uses customer_data termname when present' do
      c = Intacct::Invoice.new(composite)
      c.customer_data = OpenStruct.new(termname: "Net 60")
      h = c.content_xml
      expect(h[:termname]).to eq "Net 60"
    end
  end

  describe '#content_xml with block' do
    it 'returns self for chaining' do
      c = Intacct::Invoice.new(composite)
      result = c.content_xml { |xml| xml.invoiceno 'X' }
      expect(result).to be c
    end

    it 'stores the block in @content_xml_block' do
      c = Intacct::Invoice.new(composite)
      c.content_xml { |xml| xml.invoiceno 'X' }
      expect(c.instance_variable_get(:@content_xml_block)).to be_a(Proc)
    end

    it 'does not set @content_xml' do
      c = Intacct::Invoice.new(composite)
      c.content_xml { |xml| xml.invoiceno 'X' }
      expect(c.instance_variable_get(:@content_xml)).to be_nil
    end
  end

  # ─── XML output — hash path ──────────────────────────────────────────────────

  describe 'XML output via hash_to_xml (default path)' do
    let(:c) do
      inv = Intacct::Invoice.new(composite)
      inv.customer_data = OpenStruct.new(termname: "Net 30")
      inv
    end

    it 'renders customerid' do
      root = build_xml(c)
      expect(root.at('customerid').text).to eq customer.intacct_system_id.to_s
    end

    it 'renders termname' do
      root = build_xml(c)
      expect(root.at('termname').text).to eq "Net 30"
    end

    it 'renders invoiceno' do
      root = build_xml(c)
      expect(root.at('invoiceno').text).to eq "AUTO-#{invoice.id}"
    end

    it 'renders datecreated with nested year/month/day' do
      root = build_xml(c)
      expect(root.at('datecreated year').text).to eq invoice.created_at.strftime("%Y")
      expect(root.at('datecreated month').text).to eq invoice.created_at.strftime("%m")
      expect(root.at('datecreated day').text).to eq invoice.created_at.strftime("%d")
    end
  end

  # ─── XML output — block path ─────────────────────────────────────────────────

  describe 'XML output via custom block' do
    it 'renders only what the block produces' do
      c = Intacct::Invoice.new(composite)
      c.content_xml do |xml|
        xml.customerid 'BLOCK-CUSTOMER'
        xml.invoiceno  'CUSTOM-001'
      end
      root = build_xml(c)
      expect(root.at('customerid').text).to eq 'BLOCK-CUSTOMER'
      expect(root.at('invoiceno').text).to eq 'CUSTOM-001'
      expect(root.at('termname')).to be_nil
    end
  end

  # ─── #validate_fields! ───────────────────────────────────────────────────────

  describe '#validate_fields!' do
    context 'intacct_object_id — always-on check' do
      it 'passes when invoice has id (prefix + id fallback)' do
        expect { intacct_invoice.send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'passes when invoice defines intacct_object_id directly (no id needed)' do
        invoice.intacct_object_id = 'EXPLICIT-42'
        invoice.id = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }.not_to raise_error
      end

      it 'raises when neither id nor intacct_object_id resolves to a value' do
        invoice.id = nil
        invoice.intacct_object_id = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Invoice requires id or intacct_object_id/)
      end
    end

    context 'gem default [:created_at]' do
      it 'passes when created_at is present' do
        expect { intacct_invoice.send(:validate_fields!, :create) }.not_to raise_error
        expect { intacct_invoice.send(:validate_fields!, :update) }.not_to raise_error
      end

      it 'raises Intacct::Error when created_at is blank on create' do
        invoice.created_at = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Invoice#created_at is required for create/)
      end

      it 'raises Intacct::Error when created_at is blank on update' do
        invoice.created_at = nil
        expect { intacct_invoice.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Invoice#created_at is required for update/)
      end
    end

    context 'intacct_invoice_required_fields overridden globally' do
      before { Intacct.intacct_invoice_required_fields = [:id, :created_at, :intacct_key] }
      after  { Intacct.intacct_invoice_required_fields = nil }

      it 'applies the override to both create and update' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Invoice#intacct_key is required for create/)
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Invoice#intacct_key is required for update/)
      end
    end

    context 'only intacct_invoice_create_required_fields set' do
      before { Intacct.intacct_invoice_create_required_fields = [:id, :created_at, :intacct_key] }
      after  { Intacct.intacct_invoice_create_required_fields = nil }

      it 'validates intacct_key on create' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'also applies to update when intacct_invoice_update_required_fields is not set' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end
    end

    context 'both create and update required fields set' do
      before do
        Intacct.intacct_invoice_create_required_fields = [:id, :created_at, :intacct_key]
        Intacct.intacct_invoice_update_required_fields = [:id, :created_at]
      end
      after do
        Intacct.intacct_invoice_create_required_fields = nil
        Intacct.intacct_invoice_update_required_fields = nil
      end

      it 'uses create fields for create' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'uses update fields for update — intacct_key not required' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :update) }.not_to raise_error
      end
    end

    context 'only intacct_invoice_update_required_fields set' do
      before { Intacct.intacct_invoice_update_required_fields = [:id, :created_at, :intacct_key] }
      after  { Intacct.intacct_invoice_update_required_fields = nil }

      it 'uses update fields for update' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /intacct_key/)
      end

      it 'falls back to gem default for create — intacct_key not required' do
        invoice.intacct_key = nil
        expect { intacct_invoice.send(:validate_fields!, :create) }.not_to raise_error
      end
    end
  end

  describe 'Intacct.error_codes registry' do
    after { Intacct.instance_variable_set(:@error_codes, nil) }

    it 'includes BL03002185 by default' do
      expect(Intacct.error_codes['BL03002185']).to eq 'A transaction with that number already exists'
    end

    it 'allows registering an additional code' do
      Intacct.register_error_code('XX999', 'Custom error')
      expect(Intacct.error_codes['XX999']).to eq 'Custom error'
    end

    it 'preserves built-in codes when registering a new one' do
      Intacct.register_error_code('XX999', 'Custom error')
      expect(Intacct.error_codes['BL03002185']).to be_present
    end

    it 'allows the hash to be fully replaced' do
      Intacct.error_codes = { 'ZZ001' => 'override' }
      expect(Intacct.error_codes.keys).to eq ['ZZ001']
    end
  end

  describe 'Intacct.duplicate_transaction_error_code' do
    after { Intacct.duplicate_transaction_error_code = nil }

    it 'defaults to BL03002185' do
      expect(Intacct.duplicate_transaction_error_code).to eq 'BL03002185'
    end

    it 'can be overridden via setup' do
      Intacct.setup { |c| c.duplicate_transaction_error_code = 'CUSTOM001' }
      expect(Intacct.duplicate_transaction_error_code).to eq 'CUSTOM001'
    end
  end

  # ─── #create duplicate fallback ─────────────────────────────────────────────

  describe '#create duplicate fallback' do
    subject { intacct_invoice }

    before do
      invoice.intacct_system_id  = nil
      invoice.intacct_created_at = nil
    end

    def stub_requests(*bodies)
      responses = bodies.map { |b| instance_double(Net::HTTPResponse, code: '200', body: b) }
      call_idx = [0]
      allow_any_instance_of(Net::HTTP).to receive(:request) do
        resp = responses[call_idx[0]] || responses.last
        call_idx[0] += 1
        resp
      end
    end

    def customer_get_xml
      <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>success</status>
            <data><customer></customer></data>
          </result></operation>
        </response>
      XML
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

    def invoice_list_xml
      <<~XML
        <?xml version="1.0"?>
        <response><control><status>success</status></control>
          <operation><result><status>success</status>
            <data><invoice><key>9876</key></invoice></data>
          </result></operation>
        </response>
      XML
    end

    it 'returns true and fires after_create with self' do
      stub_requests(customer_get_xml, duplicate_xml, invoice_list_xml)
      captured = nil
      subject.after_create { |i| captured = i }
      result = subject.create
      expect(result).to be true
      expect(captured).to be subject
    end

    it 'sets intacct_system_id on the domain object' do
      stub_requests(customer_get_xml, duplicate_xml, invoice_list_xml)
      subject.create
      expect(invoice.intacct_system_id).to be_present
    end

    it 'sets intacct_created_at on the domain object' do
      stub_requests(customer_get_xml, duplicate_xml, invoice_list_xml)
      subject.create
      expect(invoice.intacct_created_at).to be_present
    end

    it 'sets intacct_key from the get_list response' do
      stub_requests(customer_get_xml, duplicate_xml, invoice_list_xml)
      subject.create
      expect(invoice.intacct_key).to eq '9876'
    end
  end

  # ─── custom_invoice_fields hook ──────────────────────────────────────────────

  describe 'custom_invoice_fields hook' do
    let(:c) do
      inv = Intacct::Invoice.new(composite)
      inv.customer_data = OpenStruct.new(termname: "Net 30")
      inv
    end

    it 'appends nodes after the default body' do
      c.custom_invoice_fields { |xml, _| xml.extra 'bonus' }
      root = build_xml(c)
      expect(root.at('customerid')).not_to be_nil
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'appends nodes after a custom block body' do
      c.content_xml { |xml| xml.customerid 'Block' }
      c.custom_invoice_fields { |xml, _| xml.extra 'bonus' }
      root = build_xml(c)
      expect(root.at('customerid').text).to eq 'Block'
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'produces no extra nodes when no hook is registered' do
      expect(build_xml(c).at('extra')).to be_nil
    end
  end
end
