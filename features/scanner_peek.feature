
Feature: Peek
	In order to provide convenient one character lookahead
	the scanner must provide the ability to "peek" at the next
	character in the input

	Scenario:  Peek should be repeatable
		Given there are two different characters in the stream
		When calling peek twice
		Then the same character should be returned both times

