# Intacct

Ruby gem for syncing financial records with the [Sage Intacct XML API](https://developer.intacct.com/web-services/).

Supports creating, reading, updating, and deleting invoices, bills, customers, and vendors.

## Installation

Add to your Gemfile:

```ruby
gem 'intacct'
```

Then run:

```
bundle install
```

## Configuration

Call `Intacct.setup` once at startup (e.g. in a Rails initializer):

```ruby
Intacct.setup do |config|
  config.xml_sender_id   = ENV['INTACCT_XML_SENDER_ID']   # Web Services sender ID issued by Intacct
  config.xml_password    = ENV['INTACCT_XML_PASSWORD']     # Web Services sender password
  config.app_user_id     = ENV['INTACCT_USER_ID']          # Your Intacct user login
  config.app_company_id  = ENV['INTACCT_COMPANY_ID']       # Your Intacct company ID
  config.app_password    = ENV['INTACCT_PASSWORD']         # Your Intacct user password

  # Optional prefixes prepended to IDs when creating records
  config.invoice_prefix  = 'INV-'
  config.bill_prefix     = 'BILL-'
  config.customer_prefix = 'C'
  config.vendor_prefix   = 'V'

  # Optional: override the Intacct gateway URL (useful for testing)
  # config.service_url = 'https://www.intacct.com/ia/xml/xmlgw.phtml'

  # Optional: HTTP timeouts in seconds
  # config.http_open_timeout = 5
  # config.http_read_timeout = 30
end
```

Use a `.env` file (via [dotenv](https://github.com/bkeepers/dotenv)) to keep credentials out of source control:

```
INTACCT_XML_SENDER_ID=your_sender_id
INTACCT_XML_PASSWORD=your_sender_password
INTACCT_USER_ID=your_user
INTACCT_COMPANY_ID=your_company
INTACCT_PASSWORD=your_password
```

## Testing Your Connection

After configuration, verify your credentials with a single call:

```ruby
Intacct.ping  # => true if credentials are valid, false otherwise
```

`ping` sends a minimal authenticated request (fetching up to 1 customer) and returns `true` on success or `false` on any failure, including network errors and invalid credentials.

## Reading Data

```ruby
# List invoices (returns a QueryResult)
result = Intacct::Invoice.list
result.records  # => Nokogiri::NodeSet of <invoice> elements

# List with a limit
result = Intacct::Invoice.list(limit: 50)

# List with a filter block
result = Intacct::Invoice.list do |xml|
  xml.filter {
    xml.expression {
      xml.field "invoiceno"
      xml.operator "="
      xml.value "INV-12345"
    }
  }
end

# List bills
result = Intacct::Bill.list

# Find a customer by their Intacct ID
result = Intacct::Customer.find(id: "C12345", fields: [:customerid, :name, :termname])
result.data  # => OpenStruct with the requested fields
```

## Writing Data

```ruby
# Create a customer
customer = OpenStruct.new(id: "12345", name: "Acme Corp")
Intacct::Customer.new(customer).create

# Create a vendor
vendor = OpenStruct.new(id: "V001", first_name: "John", last_name: "Doe", ...)
Intacct::Vendor.new(vendor).create

# Create an invoice (also creates customer/vendor if they don't have an intacct_system_id)
data = OpenStruct.new(invoice: invoice_obj, customer: customer_obj, vendor: vendor_obj)
intacct_invoice = Intacct::Invoice.new(data)
intacct_invoice.create  # => true on success

# Create a bill
data = OpenStruct.new(payment: payment_obj, customer: customer_obj, vendor: vendor_obj)
intacct_bill = Intacct::Bill.new(data)
intacct_bill.create  # => true on success
```

## Customizing XML (Important)

The gem handles authentication, request wrapping, and the structural skeleton of each resource. **It cannot know your account's custom fields or exact XML structure** — these are specific to your Intacct configuration.

You define field mappings locally using hooks inside the `Intacct.setup` block:

```ruby
Intacct.setup do |config|
  # ... credentials ...

  config.invoice do |inv|
    inv.custom_fields do |xml|
      # xml is a Nokogiri Builder — add whatever fields your account requires
      xml.customfields {
        xml.customfield {
          xml.customfieldname "YOUR_CUSTOM_FIELD"
          xml.customfieldvalue object.invoice.some_value
        }
      }
      xml.invoiceitems {
        xml.lineitem {
          xml.glaccountno 4000
          xml.amount object.invoice.total
          xml.memo object.invoice.description
        }
      }
    end
  end

  config.bill do |b|
    b.custom_fields do |xml|
      xml.billno object.payment.id
      xml.description object.payment.note
    end
  end
end
```

Inside hook blocks, `object` refers to the data object passed to the resource constructor. See `spec/steps/intacct_invoice_steps.rb` for a detailed real-world example of invoice and bill field mappings.

### Available hooks

| Hook | Resource | Purpose |
|------|----------|---------|
| `invoice.custom_fields` | Invoice | XML appended inside `create_invoice` |
| `bill.custom_fields` | Bill | Extra fields inside `create_bill` |
| `bill.bill_item_fields` | Bill | Line items inside `create_bill` |
| `bill.before_create` | Bill | Runs before the HTTP request (e.g. set a pay date) |

You can also set hooks directly on the class for more control:

```ruby
Intacct::Invoice.custom_invoice_fields do |xml|
  # ...
end

Intacct::Bill.bill_item_fields do |xml|
  xml.billitems {
    xml.lineitem {
      xml.glaccountno 5000
      xml.amount object.payment.amount
    }
  }
end
```

## Running Tests

### Unit tests (no credentials required)

```
bundle exec rspec spec/intacct_spec.rb
```

HTTP is stubbed with WebMock — no Intacct account needed.

### Integration tests (real API calls)

1. Copy the example env file and fill in your credentials:

   ```
   cp .env.example .env
   ```

2. Run a specific feature:

   ```
   INTACCT_INTEGRATION=1 bundle exec rspec spec/features/intacct_connection.feature
   INTACCT_INTEGRATION=1 bundle exec rspec spec/features/intacct_invoice.feature
   ```

3. Run all integration tests:

   ```
   INTACCT_INTEGRATION=1 bundle exec rspec spec/features/
   ```
