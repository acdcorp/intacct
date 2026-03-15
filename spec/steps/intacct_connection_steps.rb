module IntacctConnectionSteps
  step 'I have setup the correct settings' do
    default_setup
  end

  step 'pinging Intacct should succeed' do
    expect(Intacct.ping).to eq(true)
  end
end

RSpec.configure do |config|
  config.include IntacctConnectionSteps, type: :feature
end
