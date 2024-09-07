ta:
	clear && forge test -vv --match-contract Test --fork-url <YOUR ALCHEMY URL> --fork-block-number 19955703

t:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_swap_price_down" --fork-url <YOUR ALCHEMY URL> --fork-block-number 19955703
t1:
	clear && forge test -vvvv --match-contract ALMTest --match-test "test_swap_price_down" --fork-url <YOUR ALCHEMY URL> --fork-block-number 20700709
tl:
	clear && forge test -vv --match-contract ALMTest --match-test "test_swap_price_down" --fork-url <YOUR ALCHEMY URL> --fork-block-number 19955703

spell:
	clear && cspell "**/*.*"