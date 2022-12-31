<?php

    function inventory_board( $s ) {
    
        $results = array();

        $len = strlen( $s );

        // Each empty cell potentially "sees" some numbers already, from elsewhere
        // in the row, column, or 3x3 grid that it participates with. These numbers
        // identify value that the empty cell CAN NOT be.  Check each cell and 
        // save the set of numbers we are sure it ISN'T

        for ( $i = 0; $i < $len; $i++ ) {

            if ( strcmp( $s[ $i ], "0" ) != 0 ) {

                // Cell already filled in, so move on to the next character:
                $results[ $i ] = "";

                continue;

            }

            $row = intdiv( $i, 9 ); // The row of the board we are looking at
            
            // What non-zero numbers are in this row?
            $row_chars = "";
            for ( $j = 0; $j < 9; $j++ ) {

                $c = $s[ ( $row * 9 ) + $j ];

                $row_chars .= ( strpos( "123456789", $c ) === false ) ? "" : $c;

            }
            
            $col = $i % 9; // The column of the board that we are looking at
            
            // What non-zero numbers are in this column?
            $col_chars = "";
            for ( $j = 0; $j < 9; $j++ ) {

                $c = $s[ ( $j * 9 ) + $col ];

                $col_chars .= ( strpos( "123456789", $c ) === false ) ? "" : $c;

            }

            // Let's look at the 'local' 3x3 matrix the cell is in:
            $top_row = 3 * intdiv( $row, 3 );
            $top_col = 3 * intdiv( $col, 3 );

            // What non-zero numbers are in this 3x3 matrix?
            $mtx_chars = "";
            for ( $y = 0; $y < 3; $y++ ) {

                for ( $x = 0; $x < 3; $x++ ) {

                    $offset = ( ( $top_row + $y ) * 9 ) + ( $top_col + $x );

                    $c = $s[ $offset ];
                    
                    $mtx_chars .= ( strpos( "123456789", $c ) === false ) ? "" : $c;

                }
            }

            // Find the set of unique numbers this cell can already 'see'
            $unique = count_chars( $row_chars . $col_chars . $mtx_chars, 3 );
            
            // We will maintain an array to keep track of what numbers each cell
            // knows about.

            $results[ $i ] = $unique;
        }

        // Now we know what other numbers the blank cells can 'see', we can narrow
        // down what remaining numbers will work in this slot. 
        //
        // We'll return an array of possible numbers for each slot:

        $number_set = "123456789";

        $answers = array();

        for ( $i = 0; $i < $len; $i++ ) {

            if ( strcmp( $results[ $i ], "" ) == 0  ) {
                
                // Already has a number
                $answers[ $i ] = $results[ $i ];

                continue;

            }
            
            $str = $results[ $i ];

            $available = "";

            for ( $j = 0; $j < 9; $j++ ) {

                if ( strpos( $str, $number_set[ $j ]) === false ){

                    // number not found in the list of characters the cell knows about
                    $available .= $number_set[ $j ];

                }

            }

            $answers[ $i ] = $available;

        }

        return( $answers );

    }

    function solve_board( $t, $level ) {

        // Solving loop:
        //
        //   1  Inventory the board
        //  
        //   2  Identify the number of unresolved cells.  
        //
        //        A If this number = 0, then you are done
        // 
        //        B Otherwise, identify the first cell with the lowest number
        //          of alternate values.  Recursively evaluate these.
        
        $answers = inventory_board( $t );

        // If we are are done, there will be no more 0s on the board. 
        // Return state (0 = success, -1 failure), and finished board

        $remaining_gaps = substr_count( $t, "0" );

        if ( $remaining_gaps == 0 ) {

            // No more gaps left on the board.  
            // This is a solution!

            // print "This is a solution!\nL$level\n$t\n";

            return( $t );

        }

        // Otherwise, we have more work to do.  Find a slot with the fewest # of
        // alternatives to check, and loop through and try them:

        $minlen = $slot = 10;

        for ( $i = 0;$i < strlen( $t ); $i++ ) { 

            $len = strlen( $answers[ $i ] );
            
            if ( $len == 0 ) continue;

            if ( $len < $minlen ) {

                $slot = $i;

                $minlen = $len;

            }

        }

        // If we have spaces to fill but no alternatives to check, the attempted
        // solution fails:

        if ( ( $minlen == 10 ) && ( $remaining_gaps > 0 ) ) {

            return( "" );

        }

        //$b = array();

        for ( $j = 0; $j < strlen( $answers[ $slot ] ); $j++ ) {
            
            $c = $answers[ $slot ][ $j ];

            $x = $t;

            $x[ $slot ] = $c;

            $board = solve_board( $x, $level + 1 );

            if ( strcmp( $board, "" ) != 0 ) {
                return( $board );
            }

        }

    }

    // 000 000 000    374 251 968
    // 900 836 001    952 836 741
    // 081 000 520    681 974 523
    // 008 702 100    548 762 139
    // 000 090 000    126 593 874
    // 003 408 200    793 418 256
    // 015 000 690    415 387 692
    // 200 145 007    269 145 387
    // 000 000 000    837 629 415

    $s_test = "000000000900836001081000520008702100000090000003408200015000690200145007000000000";

    $board = solve_board( $s_test, 0 );

    print "Testing:  [$s_test]\n\n";
    print "Solution: [$board]\n\n";

?>