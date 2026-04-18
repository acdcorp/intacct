require 'spec_helper'

describe Intacct::Customer do
  include Helpers

  before { default_setup }

  def build_xml(c, action: :create)
    c.send(:content_xml) unless c.instance_variable_get(:@content_xml) ||
                                 c.instance_variable_get(:@content_xml_block)
    tag = action == :create ? 'create_customer' : 'update_customer'
    Nokogiri::XML::Builder.new do |xml|
      xml.send(tag) {
        xml.customerid c.intacct_object_id if action == :create
        c.send(:build_content_xml, xml)
        c.run_hook :custom_customer_fields, xml
      }
    end.doc.root
  end

  # ─── Intacct.customer_fields default ────────────────────────────────────────

  describe 'Intacct.customer_fields' do
    after { Intacct.customer_fields = nil }

    it 'returns the gem default list when not configured' do
      Intacct.customer_fields = nil
      expect(Intacct.customer_fields).to include(:customerid, :name, :termname)
    end

    it 'returns the configured list when set in setup' do
      Intacct.setup { |c| c.customer_fields = [:customerid, :name] }
      expect(Intacct.customer_fields).to eq [:customerid, :name]
    end
  end

  # ─── intacct_object_id ──────────────────────────────────────────────────────

  describe '#intacct_object_id' do
    it 'defaults to customer_prefix + id' do
      expect(Intacct::Customer.new(customer).intacct_object_id).to eq "C#{customer.id}"
    end

    it 'uses intacct_object_id from the object when present' do
      customer.intacct_object_id = 'OVERRIDE-77'
      expect(Intacct::Customer.new(customer).intacct_object_id).to eq 'OVERRIDE-77'
    end
  end

  # ─── content_xml (hash path) ────────────────────────────────────────────────

  describe '#content_xml without block' do
    subject(:h) { Intacct::Customer.new(customer).content_xml }

    it 'returns a Hash' do
      expect(h).to be_a(Hash)
    end

    it 'includes name and status' do
      expect(h[:name]).to eq customer.name
      expect(h[:status]).to eq 'active'
    end

    it 'includes a nil comments entry' do
      expect(h).to have_key(:comments)
      expect(h[:comments]).to be_nil
    end

    it 'stores the result in @content_xml' do
      c = Intacct::Customer.new(customer)
      c.content_xml
      expect(c.instance_variable_get(:@content_xml)).to be_a(Hash)
    end
  end

  describe '#content_xml with block' do
    it 'returns self for chaining' do
      c = Intacct::Customer.new(customer)
      result = c.content_xml { |xml| xml.name 'X' }
      expect(result).to be c
    end

    it 'stores the block in @content_xml_block' do
      c = Intacct::Customer.new(customer)
      c.content_xml { |xml| xml.name 'X' }
      expect(c.instance_variable_get(:@content_xml_block)).to be_a(Proc)
    end

    it 'does not set @content_xml' do
      c = Intacct::Customer.new(customer)
      c.content_xml { |xml| xml.name 'X' }
      expect(c.instance_variable_get(:@content_xml)).to be_nil
    end
  end

  # ─── XML output — hash path ──────────────────────────────────────────────────

  describe 'XML output via hash_to_xml (default path)' do
    it 'renders customerid, name, status for create' do
      root = build_xml(Intacct::Customer.new(customer), action: :create)
      expect(root.at('customerid').text).to eq "C#{customer.id}"
      expect(root.at('name').text).to eq customer.name
      expect(root.at('status').text).to eq 'active'
    end

    it 'renders name and status for update' do
      root = build_xml(Intacct::Customer.new(customer), action: :update)
      expect(root.at('name').text).to eq customer.name
      expect(root.at('status').text).to eq 'active'
    end

    it 'renders empty comments tag' do
      root = build_xml(Intacct::Customer.new(customer))
      expect(root.at('comments')).not_to be_nil
    end

    it 'reflects hash mutations' do
      c = Intacct::Customer.new(customer)
      c.content_xml[:name] = 'Mutated Name'
      expect(build_xml(c).at('name').text).to eq 'Mutated Name'
    end
  end

  # ─── XML output — block path ─────────────────────────────────────────────────

  describe 'XML output via custom block' do
    it 'renders only what the block produces' do
      c = Intacct::Customer.new(customer)
      c.content_xml do |xml|
        xml.name 'Block Name'
        xml.status 'inactive'
      end
      root = build_xml(c)
      expect(root.at('name').text).to eq 'Block Name'
      expect(root.at('status').text).to eq 'inactive'
      expect(root.at('comments')).to be_nil
    end
  end

  # ─── custom_customer_fields hook ─────────────────────────────────────────────

  describe 'custom_customer_fields hook' do
    it 'appends nodes after the default body' do
      c = Intacct::Customer.new(customer)
      c.custom_customer_fields { |xml| xml.extra 'bonus' }
      root = build_xml(c)
      expect(root.at('name').text).to eq customer.name
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'appends nodes after a custom block body' do
      c = Intacct::Customer.new(customer)
      c.content_xml { |xml| xml.name 'Block' }
      c.custom_customer_fields { |xml| xml.extra 'bonus' }
      root = build_xml(c)
      expect(root.at('name').text).to eq 'Block'
      expect(root.at('extra').text).to eq 'bonus'
    end

    it 'produces no extra nodes when no hook is registered' do
      expect(build_xml(Intacct::Customer.new(customer)).at('extra')).to be_nil
    end

    it 'can be defined at class level and fires for all instances' do
      Intacct::Customer.custom_customer_fields { |xml| xml.class_extra 'class-level' }
      root = build_xml(Intacct::Customer.new(customer))
      expect(root.at('class_extra').text).to eq 'class-level'
    ensure
      # reset class-level hooks so other tests are not affected
      Intacct::Customer._hooks[:custom_customer_fields].clear
    end
  end

  # ─── validate_fields! ────────────────────────────────────────────────────────

  describe '#validate_fields!' do
    context 'gem default [:id, :name]' do
      it 'passes when id and name are present' do
        c = Intacct::Customer.new(customer)
        expect { c.send(:validate_fields!, :create) }.not_to raise_error
        expect { c.send(:validate_fields!, :update) }.not_to raise_error
      end

      it 'raises Intacct::Error when name is blank on create' do
        customer.name = nil
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Customer#name is required for create/)
      end

      it 'raises Intacct::Error when id is blank on update' do
        customer.id = nil
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Customer#id is required for update/)
      end
    end

    context 'intacct_customer_required_fields overridden globally' do
      before { Intacct.intacct_customer_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_customer_required_fields = [:id, :name] }

      it 'applies the override to both create and update' do
        c = Intacct::Customer.new(customer)
        expect { c.send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /Customer#email is required for create/)
        expect { c.send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /Customer#email is required for update/)
      end
    end

    context 'only intacct_customer_create_required_fields set' do
      before { Intacct.intacct_customer_create_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_customer_create_required_fields = nil }

      it 'validates email on create' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'also applies to update when intacct_customer_update_required_fields is not set' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end
    end

    context 'both create and update required fields set' do
      before do
        Intacct.intacct_customer_create_required_fields = [:id, :name, :email]
        Intacct.intacct_customer_update_required_fields = [:id, :name]
      end
      after do
        Intacct.intacct_customer_create_required_fields = nil
        Intacct.intacct_customer_update_required_fields = nil
      end

      it 'uses create fields for create' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :create) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'uses update fields for update — email not required' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :update) }
          .not_to raise_error
      end
    end

    context 'only intacct_customer_update_required_fields set' do
      before { Intacct.intacct_customer_update_required_fields = [:id, :name, :email] }
      after  { Intacct.intacct_customer_update_required_fields = nil }

      it 'uses update fields for update' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :update) }
          .to raise_error(Intacct::Error, /email/)
      end

      it 'falls back to gem default for create — email not required' do
        expect { Intacct::Customer.new(customer).send(:validate_fields!, :create) }
          .not_to raise_error
      end
    end
  end

  # ─── #create duplicate fallback ─────────────────────────────────────────────

  describe '#create duplicate fallback' do
    subject { Intacct::Customer.new(customer) }

    before { customer.intacct_created_at = nil }

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
      expect(customer.intacct_system_id).to be_present
    end

    it 'sets intacct_created_at on the domain object' do
      stub_requests(duplicate_xml)
      subject.create
      expect(customer.intacct_created_at).to be_present
    end
  end
end
