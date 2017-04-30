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

# Get the very first $ value placed into offset:
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

# Get the very last $ value placed into offset:
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

# Sub to format our numbers like XX,XXX etc.. to nicely
# represent values over $999
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

# Return our correctly signed value, for when we need to return negative values :(
sub getSignedValue {

        my $val = shift;
        if ( $val >= 0 ) {
                return "+ \$" . abs($val);
        } else {
                return "- \$" . abs($val);
        }
}

sub getCurrentOffset {

	my $self = shift;
	my $cycleStart = shift; # Date that our pay month cycle starts
	my $selectedMonth = shift;
	my $selectedDay = shift;

	my $sqlQuery = $self->{dbh}->prepare("SELECT SUM(amount) FROM payments");
        $sqlQuery->execute();
	my $currentOffset = $sqlQuery->fetchrow;

	return $currentOffset;

}

sub getCurrentOffsetIncludingSavings {

	my $self = shift;
	my $cycleStart = shift; # Date that our pay month cycle starts
	my $selectedMonth = shift;
	my $selectedDay = shift;

	my $currentOffset = getCurrentOffset($self);

	my $sqlQuery = $self->{dbh}->prepare("SELECT SUM(amount) FROM savings");
        $sqlQuery->execute();
	my $currentSavings = $sqlQuery->fetchrow;

	# Return our sum
	return $currentOffset + $currentSavings;

}

# Return the amount of mortgage remaining (Pretty comma's form)
# ie: Mortgage - ( Offset + Principal )
sub getMortgageRemainingPretty {

	my $self = shift;
	my $totalMortgage = shift;

	my $mortgageRemaining = getMortgageRemaining($self, "$totalMortgage");
	$mortgageRemaining = formatNumbers("$mortgageRemaining");

	return $mortgageRemaining;
}

# Return the amount of mortgage remaining
# ie: Mortgage - ( Offset + Principal )
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

# Get Offset paid for given cycle:
sub getOffsetPaidCycle {

	my $self = shift;
	my $cycleStart = shift;
	my $cycleEnd = shift;

	my $offsetPaid = 0;

	# Get Offset Total:
	my $sqlQuery = $self->{dbh}->prepare("SELECT SUM(amount) FROM payments WHERE date >= '$cycleStart' AND date <= '$cycleEnd'");
        $sqlQuery->execute();
	$offsetPaid = $sqlQuery->fetchrow;
	#$offsetPaid = formatNumbers("$offsetPaid");

	return $offsetPaid;
}

sub getLifeAverage {

	my $self = shift;
	my $monthsPassed = shift;

	my $totalPaid = 0;
	my $sqlQuery = $self->{dbh}->prepare("SELECT SUM(amount) FROM payments");
	$sqlQuery->execute();
	$totalPaid = $sqlQuery->fetchrow;

	return sprintf("%02d", $totalPaid / $monthsPassed);
}

sub addOffsetPayment {

	my $self = shift;
	my $pdate = shift;
	my $pammount = shift;

	my $sqlQuery = $self->{dbh}->prepare("INSERT INTO payments(date,amount) VALUES ('$pdate', $pammount)");
	$sqlQuery->execute();
}

sub checkPaymentsMade {

	my $self = shift;
	my $checkDate = shift;
	my $payment = 0;

	my $sqlQuery = $self->{dbh}->prepare("SELECT COUNT(*) FROM (SELECT date FROM payments WHERE date LIKE '$checkDate%')");
	$sqlQuery->execute();
	$payment = $sqlQuery->fetchrow;
	
	return $payment;
}

1;
