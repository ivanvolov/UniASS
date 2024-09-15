test_core:
	forge test -vv --match-contract MicroSequencerTest
test_avs:
	forge test -vv --match-contract UniASSTest
ta:
	forge test -vv

spell:
	cspell "**/*.*"