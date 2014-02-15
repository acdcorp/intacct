Feature: Intacct Bill
  I need to be able to send and receive Intacct Bills.
  We need to also pass an invoice, customer and vendor when creating the object.

  Background:
    Given I have setup the correct settings
    And I have an payment, customer and vendor
    Then I create an Intacct Bill object

  Scenario Outline: It should "CRUD" a bill in Intacct
    Given I use the #<method> method
    Then I should recieve a sucessfull response

    Examples:
      | method |
      | create |
      | delete |
