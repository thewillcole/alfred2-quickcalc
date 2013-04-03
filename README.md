# QuickCalc for Alfred 2

An alternative calculator for [Alfred 2][alfred], supporting custom functions and variables, automatic parentheses matching, and percentages. It also supports k, m, and b (or thousand, million, and billion) as suffixes on a number.

It's essentially a wrapper around bc with a few extras added in.

![QuickCalc in action.][screenshot]

## Installation

Simply [download the workflow][dl] and open the file. You'll need to have the Powerpack to install workflows.

## Default functions

I've tried to add support for most of the functions from Alfred's advanced calculator.

Supported functions: `sin`, `cos`, `tan`, `log`, `log2`, `ln`, `exp`, `abs`, `sqrt`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `ceil`, `floor`, `round`, `trunc`, `rint`, `near`, `dtor`, `rtod`, `pow`, `logx`, `mod`, `min`, `max`.

Most of these should be similar to the implementation of Alfred's advanced calculator, but there are a few additions:

- `pow(x, y)` can be used to raise x to the power of y, without the integer limitations of the `^` operator in bc.
- `logx(base, x)` lets you get the log of a number with a defined base (`log` calculates with a base of 10 and `log2` with a base of 2).
- `mod(x, y)` performs the modulo operation.
- `dtor(d)` and `rtod(r)` converts between degrees and radians (this is part of Alfred's calculator, but I'm documenting them here since googling them doesn't turn up useful results).

## Defining custom functions and variables

After using the workflow at least once, you can find the custom functions/variables file at "~/Library/Application Support/Alfred 2/Workflow Data/com.clintonstrong.QuickCalc/custom.txt"

Here's an example custom.txt file:

	define f2c(q) {
	  return (q - 32) / 1.8
	}

	define c2f(q) {
	  return 1.8 * q + 32
	}

	tax = 8.25%

	vat = 20%

In this case, I just defined some functions to convert between celsius and fahrenheit, and set up some variables to use in calculations. It uses the syntax of GNU bc.

## Known bugs and limitations

When using functions that take multiple arguments, use both a comma and a space to separate the arugments. This is necessary since commas and spaces can be used as thousands separators. For example, use `min(5, 10)` instead of `min(5,10)`.

Because percent signs `%` are used for percentages, you'll need to use the `mod` function for modulo. For example: `mod(10, 3)` evaluates to 1.

Due to limitations with bc, the exponentiation operator (`^` or `**`) doesn't allow numbers to be raised to the power of a float (a number with digits after the decimal place). To get around this, you can use the `pow` function. For example, `pow(2, 2.5)` evaluates to 5.6568.

Percentages don't work as expected within functions. They still get converted (by dividing by 100), but it doesn't work correctly with addition and subtraction (`100 + 10%` evaluates to 100.10 rather than 110). Percentages should still work fine outside of functions.

The workflow currently doesn't have support for detecting locales. It expects a period `.` to be used as a decimal point, with commas, underscores, or spaces as optional thousands separators.

## More info

- [bc OS X Manual Page][man-page]
- [bc programming language on Wikipedia][wiki]
- [phodd's collection of functions][functions], some of which are used here.

[dl]: http://clintonstrong.com/alfred/Quick%20Calc.alfredworkflow
[screenshot]: http://clintonstrong.com/img/alfred/quickcalc.png
[alfred]: http://www.alfredapp.com
[man-page]: http://developer.apple.com/library/mac/#documentation/Darwin/Reference/ManPages/man1/bc.1.html
[wiki]: http://en.wikipedia.org/wiki/Bc_programming_language
[functions]: http://phodd.net/gnu-bc/