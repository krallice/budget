#!/usr/bin/perl

# File: NavuaAO.pm
# Perl package/class for interfacing with navua.db. Bit of a practise/learning curve with the Data Access Object (DAO) design pattern.
# Replacing code that directly interfaced with the database

package NavuaAO;

use strict;
use warnings;

use DBI;
use Carp;

# Init our Navua Access Object: 
sub new {

	# Init ourselves:
	my $class = shift;
	my $self = { @_ };
	# Ensure filename for DB is given by caller:
	croak "Bad Arguments" unless defined $self->{filename};

	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}");

	return bless $self, $class;
}

# Return our database name:
sub getFilename {
	my $self = shift;
	return "$self->{filename}";
}

# Get the First $ value placed into offset:
sub getFirstOffsetValue {

	my $self = shift;
        my $sqlQuery = $self->{dbh}->prepare("SELECT amount FROM payments LIMIT 1");
        $sqlQuery->execute();

	my $value = "";
        while ( my $row = $sqlQuery->fetchrow_hashref ) {
		$value = $row->{amount};
	}
	
	return $value;
}

# Get the First $ value placed into offset:
sub getLastOffsetValue {

	my $self = shift;
        my $sqlQuery = $self->{dbh}->prepare("SELECT amount FROM payments ORDER BY date DESC LIMIT 1");
        $sqlQuery->execute();

	my $value = "";
        while ( my $row = $sqlQuery->fetchrow_hashref ) {
		$value = $row->{amount};
	}
	
	return $value;
}

# Sub to format our numbers like XX,XXX etc..
sub formatNumbers {

        # Read our number reverse, and then split into an array:
        my $val = reverse shift;
        my @a = split("", $val);

        # Our return array:
        my @r;

        # If we have a complex number:
        if ( (scalar @a + 1) > 3) {

                # Iterate through the length:
                for my $i ( 0 .. $#a ) {
                        if ( (($i + 1) % 3) == 0) {
                                if ( $i != $#a ) {
                                        unshift(@r, "," . $a[$i]);
                                } else {
                                        unshift(@r, $a[$i]);
                                }
                        } else {
                                unshift(@r, $a[$i]);
                        }
                }
        }

        # Flatten to scalar and return:
        return join("", @r);
}

# Return correctly signed value:
sub getSignedValue {

        my $val = shift;
        if ( $val >= 0 ) {
                return "+ \$" . abs($val);
        } else {
                return "- \$" . abs($val);
        }
}

sub getMortgageRemainingPretty {

	my $self = shift;
	my $totalMortgage = shift;

	my $mortgageRemaining = getMortgageRemaining($self, "$totalMortgage");
	$mortgageRemaining = formatNumbers("$mortgageRemaining");

	return $mortgageRemaining;
}

sub getMortgageRemaining {

	my $self = shift;
	my $totalMortgage = shift;

	# Get Offset Total:
	my $sqlQuery = $self->{dbh}->prepare("SELECT SUM(amount) FROM payments");
        $sqlQuery->execute();
	my $offsetTotal = $sqlQuery->fetchrow;

	my $mortgageRemaining = $totalMortgage - $offsetTotal;

	return $mortgageRemaining;
}
1;
