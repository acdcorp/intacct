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
