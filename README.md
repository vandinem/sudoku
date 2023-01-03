# sudoku

Various of my sudoku solver scripts collected in one place

The .txt files are just text representations of unsolved Sudoku boards.  A board consists of 81 characters, every 9 representing the next row of the board.  A blank space (' ') or a zero ('0') is a placeholder for an unfilled cell.
So the file named '2012-06-12 Boston Globe.txt' is just this line:

`090107080050306020007000600023040710700000004045030860009000200010608040060209070`

Which represents this board:

```
090 | 107 | 080       9  | 1 7 |  8 
050 | 306 | 020       5  | 3 6 |  2 
007 | 000 | 600        7 |     | 6  
---------------      ---------------
023 | 040 | 710       23 |  4  | 71 
700 | 000 | 004  OR  7   |     |   4
045 | 030 | 860       45 |  3  | 86 
---------------      ---------------
009 | 000 | 200        9 |     | 2  
010 | 608 | 040       1  | 6 8 |  4 
060 | 209 | 070       6  | 2 9 |  7 
```

The **[basic_sudoku.pl](basic_sudoku.pl)** perl script was culled from my first solver attempt long ago.  This script was all over the place and has not been rigorously tested (it fails on some boards that other scripts handle without issue ... but I haven't tried to track down why.)  My Perl had gotten better at this point, although my understanding of the puzzle had not.  The script takes 1,100+ lines to accomplish what the site's PHP version manages in about 200 lines (**[sudtest.php](sudtest.php)** excerpts the key code into a console script) .  I think the approach is similar in spirit between the two.  I'd solved a lot more sudoku boards by the time I got to the PHP attempt, though, and was smarter about using some built-in functions when examining the boards and choosing numbers.

The **[depthfirst.pl](depthfirst.pl)** perl script is a Windows-only solver that employs a depth-first search for a solution.  It is Windows-only by use of the Win32::Console::ANSI library that it uses to provide a character-based animation in the console box of the algorithm as it tries to find a solution.  This could probably be replaced with another platform-independent module (I think I've used Term::ANSIColor elsewhere).  This animation looks kind of cool, but makes the whole process VERY slow.  Almost unbearable so.  I had expected the tree-pruning action of the algorithm to converge on a solution way faster than it does ... I guess the tree was a lot bigger than I originally imagined.

The **[dfirstcmd.pl](dfirstcmd.pl)** script revises **[depthfirst.pl](depthfirst.pl)** to step around the animation by default. The -V option to the script will set 'verbose' and show the animation if wanted. The -G option will display the non-verbose solution(s) as a simple grid (easier to read) while the default will sent the solution to STDOUT in a single line (useful if you feed the script a file of boards to solve and want to redirect the solutions into another file.
