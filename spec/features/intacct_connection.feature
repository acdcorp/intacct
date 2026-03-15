Feature: Intacct Connection
  Scenario: Test connection with valid credentials
    Given I have setup the correct settings
    Then pinging Intacct should succeed
