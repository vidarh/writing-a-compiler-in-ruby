
Feature: Unget
	In order to provide more lookahead than one character the scanner
	should provide a way of pushing characters back onto the input
	stream.

	Scenario: A character that is "ungot" should be returned again on the next get
		Given there are two different characters in the stream
		When calling get 1 time
		And calling unget with the returned character
		And calling get 1 time
		Then the first character in the stream should be returned both times

	Scenario: A string that is "ungot" should be returned again on subsequent gets in the right order
		Given there are two different characters in the stream
		When calling get 2 times
		And calling unget once with a string consisting of both characters
		And calling get 2 times
		Then both characters should be returned


