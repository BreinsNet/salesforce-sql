@misc
Feature: Miscelaneous features

  In order to use sfsoql command line application
  As a salesforce developer
  I want to be able to run sfsoql queries

  Scenario: I should be able to check the version
    When I run `sfsoql -v` interactively
    Then the exit status should be 0
    And the output should match /sfsoql \d+\.\d+.\d+/
