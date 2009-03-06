
Feature: Get
	In order to retrieve data from the stream, the scanner
	should provide a way of retrieving a single character from
	the input

	Scenario: Get should retrieve each character in the stream in turn
		Given there are two different characters in the stream
		When calling get 3 times
		Then both characters should be returned followed by nil
