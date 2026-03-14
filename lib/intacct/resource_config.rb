module Intacct
  # Unified configuration object yielded by Intacct.setup.
  #
  # Supports the legacy flat-attribute API (backwards compatible):
  #   config.xml_sender_id = "..."
  #   config.invoice_prefix = "INV-"
  #
  # And the new per-resource API:
  #   config.invoice { |inv| inv.custom_fields { |xml| ... } }
  #   config.bill    { |b|   b.before_create   { object.payment.set_pay_date } }
  #   config.after_success { |resource| resource.object.save! }
  #   config.on_error      { |resource| MyLog.record(resource) }
  #
  class ResourceConfig
    class PerResourceConfig
      attr_reader :custom_fields_block, :before_create_block

      def custom_fields(&block)
        @custom_fields_block = block
      end

      def before_create(&block)
        @before_create_block = block
      end
    end

    def initialize
      @invoice_config          = nil
      @bill_config             = nil
      @after_success_callbacks = []
      @on_error_callbacks      = []
    end

    # ---------- per-resource DSL ----------

    def invoice(&block)
      @invoice_config ||= PerResourceConfig.new
      block.call(@invoice_config) if block
      @invoice_config
    end

    def bill(&block)
      @bill_config ||= PerResourceConfig.new
      block.call(@bill_config) if block
      @bill_config
    end

    def after_success(&block)
      @after_success_callbacks << block if block
      @after_success_callbacks
    end

    def on_error(&block)
      @on_error_callbacks << block if block
      @on_error_callbacks
    end

    # Apply collected resource config into the gem hooks.
    # Called once by Intacct.setup after the block finishes.
    def apply!
      if @invoice_config&.custom_fields_block
        Intacct::Invoice.custom_invoice_fields(&@invoice_config.custom_fields_block)
      end

      if @bill_config&.custom_fields_block
        Intacct::Bill.custom_bill_fields(&@bill_config.custom_fields_block)
      end

      if @bill_config&.before_create_block
        Intacct::Bill.before_create(&@bill_config.before_create_block)
      end

      @after_success_callbacks.each do |cb|
        [:after_create, :after_update, :after_delete].each do |hook|
          Intacct::Base.send(hook) { cb.call(self) }
        end
      end

      @on_error_callbacks.each do |cb|
        Intacct::Base.on_error { cb.call(self) }
      end
    end

    # ---------- legacy flat-attribute forwarding ----------

    def method_missing(name, *args, &block)
      if Intacct.respond_to?(name)
        Intacct.send(name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      Intacct.respond_to?(name, include_private) || super
    end
  end
end
