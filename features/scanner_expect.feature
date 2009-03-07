
Feature: Expect
	In order to match strings and complex tokens from the stream,
	the scanner provides a way to either match a string character by
	character, or provide a custom class to do matching

	Scenario: Expect of a string should return the string
		Given there are two different characters in the stream
		When calling expect with the two characters
		Then both characters should be returned
 