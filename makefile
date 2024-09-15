test_core:
	forge test -vv --match-contract UniASS
test_avs:
	forge test -vv --match-contract MicroSequencer
ta:
	forge test -vv

spell:
	cspell "**/*.*"